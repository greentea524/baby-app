import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/volume_entry.dart';
import '../../data/models/feeding_event.dart' show BreastSide;
import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import '../common/volume_field.dart';

/// Opens the pumping quick-log sheet (KAN-145). Pass [existing] to edit.
Future<void> showPumpingQuickLog(
  BuildContext context, {
  PumpingEvent? existing,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _PumpingSheet(existing: existing),
  );
}

class _PumpingSheet extends ConsumerStatefulWidget {
  const _PumpingSheet({this.existing});

  final PumpingEvent? existing;

  @override
  ConsumerState<_PumpingSheet> createState() => _PumpingSheetState();
}

class _PumpingSheetState extends ConsumerState<_PumpingSheet> {
  final _amount = TextEditingController();
  final _duration = TextEditingController();
  final _notes = TextEditingController();
  BreastSide _side = BreastSide.both;
  late DateTime _time;
  late VolumeUnit _unit;
  bool _busy = false;

  /// See the bottle form: an amount that was never retyped must be stored
  /// unchanged, or re-parsing the display unit rewrites a number nobody
  /// touched.
  double? _storedMl;
  bool _amountEdited = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _time = e?.time ?? DateTime.now();
    _side = e?.side ?? BreastSide.both;
    _unit = VolumeUnit.initial;
    _storedMl = e?.amountMl;
    if (e?.amountMl != null) {
      _amount.text = _unit.fieldText(e!.amountMl!);
    }
    if (e?.durationMinutes != null) {
      _duration.text = e!.durationMinutes!.toString();
    }
    if (e?.notes != null) _notes.text = e!.notes!;
  }

  @override
  void dispose() {
    _amount.dispose();
    _duration.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(pumpingRepositoryProvider);
    if (repo == null) {
      _snack('No baby selected.');
      return;
    }
    final event = PumpingEvent(
      id: widget.existing?.id ?? '',
      time: _time,
      side: _side,
      amountMl: _amountMl(),
      durationMinutes: int.tryParse(_duration.text.trim()),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    setState(() => _busy = true);
    try {
      if (widget.existing != null) {
        await repo.update(event);
      } else {
        await repo.add(event);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The amount to store: what was typed, converted, or the stored value
  /// untouched when the field was never edited.
  double? _amountMl() {
    final typed = double.tryParse(_amount.text.trim());
    if (typed == null) return _amountEdited ? null : _storedMl;
    if (!_amountEdited && _storedMl != null) return _storedMl;
    return _unit.toMl(typed);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isEdit ? 'Edit pumping' : 'Log pumping',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        SegmentedButton<BreastSide>(
          segments: const [
            ButtonSegment(value: BreastSide.left, label: Text('Left')),
            ButtonSegment(value: BreastSide.right, label: Text('Right')),
            ButtonSegment(value: BreastSide.both, label: Text('Both')),
          ],
          selected: {_side},
          onSelectionChanged: (s) => setState(() => _side = s.first),
        ),
        const SizedBox(height: 16),
        // Amount takes its own line now that it carries a unit toggle;
        // three controls abreast do not fit a phone.
        VolumeField(
          controller: _amount,
          unit: _unit,
          autofocus: !isEdit,
          onUnitChanged: (unit, text) => setState(() {
            _unit = unit;
            _amount.text = text;
          }),
          onChanged: (_) => _amountEdited = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Duration',
            suffixText: 'min',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        EventTimeRow(time: _time, onChanged: (t) => setState(() => _time = t)),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          // Only reachable by editing a record that was already stamped
          // ahead; the row above says why the button is dead.
          onPressed: _busy || isFutureLogTime(_time) ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save changes' : 'Save'),
        ),
      ],
    );
  }
}
