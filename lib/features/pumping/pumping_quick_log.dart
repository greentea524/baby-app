import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_entry.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/feeding_event.dart' show BreastSide;
import '../../data/models/fridge_bottle.dart';
import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import '../common/number_input.dart';
import '../common/save_and_close.dart';
import '../common/volume_field.dart';
import '../fridge/bottle_sheet.dart' show UpNextSwitch;
import '../fridge/vessel_pref.dart';
import '../home/home_prefs.dart';

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

  /// Guards against a second tap landing while the sheet is closing. There
  /// is no spinner any more — the sheet goes immediately (#21) — so this is
  /// all that stands between an impatient double-tap and two records.
  bool _saving = false;

  /// See the bottle form: an amount that was never retyped must be stored
  /// unchanged, or re-parsing the display unit rewrites a number nobody
  /// touched.
  double? _storedMl;
  bool _amountEdited = false;

  /// Whether this session goes in the fridge too. Off every time the sheet
  /// opens rather than remembered: most pumped milk is fed fresh, and a
  /// switch left on from last time is easy to save past without noticing,
  /// putting a bottle on the shelf that never went in the fridge.
  bool _fridgeOn = false;

  /// Whether that bottle is the one up next. Off each time too.
  bool _upNext = false;

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

  void _save() {
    if (_saving) return;
    final repo = ref.read(pumpingRepositoryProvider);
    if (repo == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No baby selected.')));
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
    // Only for a new session with milk to bottle. Editing a session is not
    // pumping it again, and a bottle of nothing is not a bottle.
    final bottling = _toFridge && event.amountMl != null && event.amountMl! > 0;
    final fridge = ref.read(fridgeRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    _saving = true;
    saveAndClose(context, () {
      // The new session's id is known before its write finishes, so the
      // bottle can say which session it is.
      final Future<void> write;
      FridgeBottle? bottle;
      if (widget.existing != null) {
        write = repo.update(event);
      } else {
        final added = repo.addNow(event);
        write = added.written;
        if (bottling) {
          bottle = FridgeBottle(
            id: '',
            // The session's own time: the milk is as old as the pumping.
            filledAt: event.time,
            amountMl: event.amountMl!,
            pumpId: added.id,
            // In what this household keeps its milk in.
            vessel: ref.read(lastVesselProvider),
            queuedAt: _upNext ? DateTime.now() : null,
          );
        }
      }
      // Alongside rather than after: offline, the session's write does not
      // finish until the device is back online, and the bottle should be on
      // the shelf now. Reports its own failure, since the session itself was
      // saved.
      if (bottle case final b? when fridge != null) {
        // One up next at a time: this one takes the place of any other.
        if (b.queuedAt != null) {
          unawaited(fridge.unqueue(ref.read(fridgeShelfProvider)));
        }
        unawaited(
          Future<void>.sync(() => fridge.add(b)).catchError((Object e) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'The session is logged, but the bottle could not be '
                  'added to the fridge: $e',
                ),
              ),
            );
          }),
        );
      }
      return write;
    }, failure: 'Could not save the pumping session');
  }

  /// Whether this session goes in the fridge too: new sessions only, and
  /// only with the fridge shown and the switch turned on for this one.
  bool get _toFridge =>
      widget.existing == null && ref.read(showFridgeProvider) && _fridgeOn;

  /// The amount to store: what was typed, converted, or the stored value
  /// untouched when the field was never edited.
  double? _amountMl() => resolveAmountMl(
    typed: double.tryParse(_amount.text.trim()),
    unit: _unit,
    storedMl: _storedMl,
    edited: _amountEdited,
  );

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
          onChanged: (_) => setState(() => _amountEdited = true),
        ),
        // Under the amount, because the amount is what goes in the bottle.
        if (!isEdit && ref.watch(showFridgeProvider)) ...[
          _FridgeToggle(
            on: _fridgeOn,
            amountMl: _amountMl(),
            onChanged: (v) => setState(() => _fridgeOn = v),
          ),
          // Whether that bottle is the one to feed next: only once it is
          // going in the fridge at all.
          if (_fridgeOn)
            UpNextSwitch(
              value: _upNext,
              onChanged: (v) => setState(() => _upNext = v),
            ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          inputFormatters: wholeNumberInput,
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
          onPressed: isFutureLogTime(_time) ? null : _save,
          child: Text(isEdit ? 'Save changes' : 'Save'),
        ),
      ],
    );
  }
}

/// "Add to the fridge", off until it is turned on for this session.
///
/// Says what it will do with this session rather than only that it is on.
/// With no amount yet it says the bottle is waiting on one, rather than
/// looking on while the save quietly adds nothing.
class _FridgeToggle extends ConsumerWidget {
  const _FridgeToggle({
    required this.on,
    required this.amountMl,
    required this.onChanged,
  });

  final bool on;
  final double? amountMl;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    final ml = amountMl;
    // What it will go in: a bottle, or this household's containers.
    final vessel = ref.watch(lastVesselProvider).label.toLowerCase();
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.kitchen_outlined),
      title: const Text('Add to the fridge'),
      subtitle: Text(switch ((on, ml)) {
        (false, _) => 'Also store it as a $vessel on the shelf',
        (true, final ml?) when ml > 0 =>
          'As a ${formatVolume(ml, units)} $vessel',
        (true, _) => 'Once there is an amount',
      }),
      value: on,
      onChanged: onChanged,
    );
  }
}
