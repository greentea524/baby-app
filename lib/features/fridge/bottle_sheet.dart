import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_entry.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/action_snack_bar.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import '../common/save_and_close.dart';
import '../common/volume_field.dart';

/// Adds a bottle to the fridge, or edits one already in it.
///
/// [prefillFrom] is the session a new bottle opens on — where the milk came
/// from nine times in ten. Passed in rather than read from a provider inside
/// the sheet: the last-pump stream is only live while something is watching
/// it, and a sheet that reached for it itself would find it still loading and
/// silently open blank.
Future<void> showBottleSheet(
  BuildContext context, {
  FridgeBottle? existing,
  PumpingEvent? prefillFrom,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _BottleSheet(existing: existing, prefillFrom: prefillFrom),
  );
}

class _BottleSheet extends ConsumerStatefulWidget {
  const _BottleSheet({this.existing, this.prefillFrom});

  final FridgeBottle? existing;
  final PumpingEvent? prefillFrom;

  @override
  ConsumerState<_BottleSheet> createState() => _BottleSheetState();
}

class _BottleSheetState extends ConsumerState<_BottleSheet> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _filledAt;
  late VolumeUnit _unit;
  late BottleKind _kind;

  /// Whether the time has been picked by hand, so switching kind knows
  /// whether it may move it. See [_setKind].
  bool _timeEdited = false;

  /// Guards a second tap landing while the sheet closes, as the other sheets
  /// do — there is no spinner to hide behind (#21).
  bool _saving = false;

  /// See the bottle form: an amount nobody retyped must be stored unchanged,
  /// or re-parsing the display unit rewrites a number nobody touched.
  double? _storedMl;
  bool _amountEdited = false;

  @override
  void initState() {
    super.initState();
    _unit = VolumeUnit.initial;
    final e = widget.existing;
    if (e != null) {
      _kind = e.kind;
      _filledAt = e.filledAt;
      _storedMl = e.amountMl;
      _amount.text = _unit.fieldText(e.amountMl);
      if (e.notes != null) _notes.text = e.notes!;
      return;
    }

    // Expressed to begin with, because the prefill below only makes sense for
    // it and because a household that pumps is the one that has a fridge full
    // of bottles to keep track of. Formula is one tap away.
    _kind = BottleKind.expressed;

    // A new bottle almost always holds the session just logged, so it opens
    // on that session's time and yield rather than on now and empty. Taken
    // once here rather than watched: these are starting values to correct,
    // and a field that changed under the caregiver mid-edit would be worse
    // than one that started blank.
    final last = widget.prefillFrom;
    _filledAt = last?.time ?? DateTime.now();
    _storedMl = last?.amountMl;
    if (last?.amountMl != null) _amount.text = _unit.fieldText(last!.amountMl!);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Switches kind, taking the fields that no longer apply with it.
  ///
  /// A formula bottle stamped with a pump session's time and yield would be
  /// wrong data, quietly — so choosing Formula clears what was prefilled from
  /// the pump, and choosing Breast milk puts it back. Only the fields nobody
  /// has touched: an amount or a time typed by hand is an answer, and moving
  /// it would be overruling the person holding the bottle.
  void _setKind(BottleKind kind) {
    setState(() {
      _kind = kind;
      final prefill = widget.prefillFrom;
      if (!_amountEdited) {
        final ml = kind == BottleKind.expressed ? prefill?.amountMl : null;
        _storedMl = ml;
        _amount.text = ml == null ? '' : _unit.fieldText(ml);
      }
      if (!_timeEdited) {
        _filledAt = kind == BottleKind.expressed
            ? (prefill?.time ?? DateTime.now())
            : DateTime.now();
      }
    });
  }

  double? get _amountMl => resolveAmountMl(
    typed: double.tryParse(_amount.text.trim()),
    unit: _unit,
    storedMl: _storedMl,
    edited: _amountEdited,
  );

  void _save() {
    if (_saving) return;
    final repo = ref.read(fridgeRepositoryProvider);
    final ml = _amountMl;
    if (repo == null || ml == null || ml <= 0) return;

    final existing = widget.existing;
    final bottle = FridgeBottle(
      id: existing?.id ?? '',
      filledAt: _filledAt,
      amountMl: ml,
      kind: _kind,
      position: existing?.position,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    _saving = true;
    saveAndClose(
      context,
      () => existing != null ? repo.update(bottle) : repo.add(bottle),
      failure: 'Could not save the bottle',
    );
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isEdit = existing != null;
    final ml = _amountMl;
    // Zero is not a bottle, and the rules reject one. Checked here so the
    // button is dead rather than the save failing after the sheet has gone.
    final canSave = ml != null && ml > 0 && !isFutureLogTime(_filledAt);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isEdit ? 'Edit bottle' : 'Add a bottle',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        // First, because it changes what the fields under it mean — and, for
        // a new bottle, what they start out holding.
        SegmentedButton<BottleKind>(
          segments: [
            for (final k in BottleKind.values)
              ButtonSegment(value: k, icon: Icon(k.icon), label: Text(k.label)),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => _setKind(s.first),
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 12),
        // Labelled for what it means here, and the label changes with the
        // kind: the field is the same one every sheet uses, but "Pumped
        // 11:00" and "Made up 11:00" are different facts, and on a bottle
        // that fact is how old the milk is.
        EventTimeRow(
          time: _filledAt,
          label: _kind.filledLabel,
          onChanged: (t) => setState(() {
            _filledAt = t;
            _timeEdited = true;
          }),
        ),
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
          onPressed: canSave ? _save : null,
          child: Text(isEdit ? 'Save changes' : 'Add to fridge'),
        ),
        // Both reached from the bottle rather than from the shelf, so every
        // bottle has exactly one tap target and the shelf stays a shelf.
        if (isEdit) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.call_split),
                  label: const Text('Split'),
                  onPressed: () {
                    // Replaces this sheet rather than stacking on it: the
                    // split sheet is the same decision continued, and coming
                    // back to a half-filled edit form afterwards would be
                    // showing an amount that is no longer the bottle's.
                    Navigator.of(context).pop();
                    showSplitSheet(context, bottle: existing);
                  },
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _remove(existing),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Takes the bottle off the shelf, with a way back.
  ///
  /// No confirmation dialog. Removing is how this screen is *used* — a bottle
  /// comes out of the fridge several times a day — and a prompt on the common
  /// action is one people learn to tap through. Undo is the better guard: it
  /// costs nothing when the removal was meant, and it is still there when it
  /// was not.
  void _remove(FridgeBottle bottle) {
    if (_saving) return;
    final repo = ref.read(fridgeRepositoryProvider);
    if (repo == null) return;
    // Captured before the pop, like saveAndClose does: afterwards this
    // context is defunct, and that is exactly when the message is shown.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    _saving = true;

    unawaited(
      Future.sync(() => repo.delete(bottle.id)).catchError((Object e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not remove the bottle: $e')),
        );
      }),
    );
    navigator.pop();

    // Six seconds, then gone. Long enough to reach Undo with a bottle in
    // the other hand, short enough that it is not still covering the shelf
    // after the moment for undoing has passed.
    messenger.showSnackBar(
      actionSnackBar(
        content: const Text('Bottle removed'),
        actionLabel: 'Undo',
        // Re-added rather than restored: the document is gone, so this is a
        // new one carrying the same milk. It keeps its position, so it goes
        // back to the slot on the shelf it came from.
        //
        // The removed bottle itself, not a copy spelled out field by field.
        // It used to be the latter, and when formula arrived the copy never
        // learned about `kind` — undoing a formula bottle brought it back as
        // breast milk. `add` stores the fields and ignores the id, so handing
        // it the original keeps every field, including ones not written yet.
        onAction: () => unawaited(
          // The id `add` returns is of no use here, and a catchError on a
          // Future<String> would have to invent one.
          Future<void>.sync(() async {
            await repo.add(bottle);
          }).catchError((Object e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not put it back: $e')),
            );
          }),
        ),
      ),
    );
  }
}

/// Asks how to divide [bottle], and splits it.
///
/// A slider rather than a typed amount. The question is "how much of this
/// goes in the other bottle", which is a proportion of something you are
/// holding, and both halves have to be shown at once for the answer to mean
/// anything.
Future<void> showSplitSheet(
  BuildContext context, {
  required FridgeBottle bottle,
}) {
  return showAppSheet<void>(context, builder: (_) => _SplitSheet(bottle));
}

class _SplitSheet extends ConsumerStatefulWidget {
  const _SplitSheet(this.bottle);

  final FridgeBottle bottle;

  @override
  ConsumerState<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<_SplitSheet> {
  late double _firstMl;
  bool _saving = false;

  /// The smallest either half may be.
  ///
  /// Not zero: a split that leaves one side empty is a split that did not
  /// happen, and the rules refuse a bottle of nothing. Five millilitres is
  /// also about the least anyone pours on purpose.
  static const _floor = 5.0;

  @override
  void initState() {
    super.initState();
    _firstMl = (widget.bottle.amountMl / 2).roundToDouble();
  }

  void _split() {
    if (_saving) return;
    final repo = ref.read(fridgeRepositoryProvider);
    if (repo == null) return;
    _saving = true;
    saveAndClose(
      context,
      () => repo.split(
        widget.bottle,
        _firstMl,
        shelf: ref.read(fridgeShelfProvider),
      ),
      failure: 'Could not split the bottle',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final total = widget.bottle.amountMl;
    final rest = total - _firstMl;
    // A bottle too small to divide: the slider would have no room to move.
    final divisible = total >= _floor * 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Split this bottle', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          divisible
              ? 'Both bottles stay ${widget.bottle.kind.label.toLowerCase()}, '
                    'and both keep the time on this one — it is no younger '
                    'for being poured into two.'
              : 'There is not enough here to divide.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (divisible) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatVolume(_firstMl, units),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatVolume(rest, units),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: _firstMl,
            min: _floor,
            max: total - _floor,
            // Whole millilitres. The two halves have to add back up to the
            // bottle, so the step cannot be a fraction the display rounds.
            divisions: (total - _floor * 2).round().clamp(1, 1000),
            label: formatVolume(_firstMl, units),
            onChanged: (v) => setState(() => _firstMl = v.roundToDouble()),
          ),
          const SizedBox(height: 4),
          Text(
            'Adds up to ${formatVolume(total, units)}.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _split,
            child: const Text('Split into two bottles'),
          ),
        ],
      ],
    );
  }
}
