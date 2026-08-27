import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/diaper_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import '../common/save_and_close.dart';
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

  /// Guards against a second tap landing while the sheet is closing. There
  /// is no spinner any more — the sheet goes immediately (#21) — so this is
  /// all that stands between an impatient double-tap and two records.
  bool _saving = false;

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

  void _save() {
    if (_saving) return;
    final repo = ref.read(diaperRepositoryProvider);
    if (repo == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No baby selected.')));
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
    _saving = true;
    saveAndClose(
      context,
      () => widget.existing != null ? repo.update(event) : repo.add(event),
      failure: 'Could not save the diaper change',
    );
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
            if (_type == DiaperType.wet) {
              // A wet-only change has nothing to size, so a size picked
              // before the type was changed goes with it.
              _size = null;
            } else {
              // Small is the common one, so choosing "dirty" chooses it too
              // and the usual log is one tap rather than two. Still not
              // required: tapping it again clears it.
              //
              // Only on a change made here, never on opening an existing
              // entry — a dirty diaper logged without a size was logged
              // that way on purpose, and saving it back with one invents a
              // measurement nobody took.
              _size ??= PoopSize.small;
            }
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
          onPressed: isFutureLogTime(_time) ? null : _save,
          child: Text(isEdit ? 'Save changes' : 'Save'),
        ),
      ],
    );
  }
}
