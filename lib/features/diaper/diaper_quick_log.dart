import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/diaper_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import 'diaper_format.dart';

/// Opens the diaper quick-log sheet. Pass [existing] to edit (KAN-150);
/// omit it to log a new change (KAN-148).
Future<void> showDiaperQuickLog(BuildContext context, {DiaperEvent? existing}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _DiaperSheet(existing: existing),
  );
}

class _DiaperSheet extends ConsumerStatefulWidget {
  const _DiaperSheet({this.existing});

  final DiaperEvent? existing;

  @override
  ConsumerState<_DiaperSheet> createState() => _DiaperSheetState();
}

class _DiaperSheetState extends ConsumerState<_DiaperSheet> {
  late DiaperType _type;
  late DateTime _time;
  PoopSize? _size;
  final _notesController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? DiaperType.wet;
    _time = e?.time ?? DateTime.now();
    _size = e?.poopSize;
    if (e?.notes != null) _notesController.text = e!.notes!;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(diaperRepositoryProvider);
    if (repo == null) {
      _snack('No baby selected.');
      return;
    }
    final event = DiaperEvent(
      id: widget.existing?.id ?? '',
      type: _type,
      time: _time,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      poopSize: _size,
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
          isEdit ? 'Edit diaper change' : 'Log a diaper change',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        SegmentedButton<DiaperType>(
          segments: [
            for (final t in DiaperType.values)
              ButtonSegment(
                value: t,
                icon: Icon(DiaperFormat.typeIcon(t)),
                label: Text(DiaperFormat.typeLabel(t)),
              ),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() {
            _type = s.first;
            // A wet-only change has nothing to size, so a size picked before
            // the type was changed goes with it.
            if (_type == DiaperType.wet) _size = null;
          }),
        ),
        // Only where there is something to measure, and never required —
        // tapping the chosen size again clears it.
        if (_type != DiaperType.wet) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Poop size (optional)',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 6),
          SegmentedButton<PoopSize>(
            segments: [
              for (final size in PoopSize.values)
                ButtonSegment(value: size, label: Text(size.label)),
            ],
            emptySelectionAllowed: true,
            selected: {?_size},
            onSelectionChanged: (s) =>
                setState(() => _size = s.isEmpty ? null : s.first),
          ),
        ],
        const SizedBox(height: 16),
        EventTimeRow(time: _time, onChanged: (t) => setState(() => _time = t)),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Notes (color / consistency, optional)',
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
