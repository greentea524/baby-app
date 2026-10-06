import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_entry.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import '../common/milk_chooser.dart';
import '../common/save_and_close.dart';
import '../common/volume_field.dart';
import '../feeding/feeding_format.dart';
import 'fridge_order.dart';

/// Adds a bottle to the fridge, or edits one already in it.
///
/// [prefillFrom] is the session a new bottle takes its amount from — where the
/// milk came from nine times in ten. Passed in rather than read from a provider inside
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
  late MilkKind _kind;

  /// The session this bottle's amount is filled in from, if any.
  PumpingEvent? get _prefill => widget.prefillFrom;

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
    _kind = MilkKind.expressed;

    // Now, always. It used to open on the pump session's time, which read as
    // a field stuck on an old value — and was plainly wrong whenever the
    // bottle was not that session's milk.
    _filledAt = DateTime.now();

    // A new bottle usually holds the session just logged, so it opens on
    // that session's yield rather than empty. Taken once here rather than
    // watched: a starting value to correct, and a field that changed under
    // the caregiver mid-edit would be worse than one that started blank.
    final last = widget.prefillFrom;
    _storedMl = last?.amountMl;
    if (last?.amountMl != null) _amount.text = _unit.fieldText(last!.amountMl!);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Switches kind, taking the amount with it if it no longer applies.
  ///
  /// A formula bottle holding a pump session's yield would be wrong data,
  /// quietly — so choosing Formula clears the amount prefilled from the pump,
  /// and choosing Breast milk puts it back. Only while nobody has typed in
  /// it: an amount typed by hand is an answer, and moving it would be
  /// overruling the person holding the bottle.
  void _setKind(MilkKind kind) {
    setState(() {
      _kind = kind;
      if (!_amountEdited) {
        final ml = kind == MilkKind.expressed ? _prefill?.amountMl : null;
        _storedMl = ml;
        _amount.text = ml == null ? '' : _unit.fieldText(ml);
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
        MilkChooser(value: _kind, onChanged: _setKind),
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
          onChanged: (t) => setState(() => _filledAt = t),
        ),
        // Says where the amount came from, while it still does.
        if (_prefill case final session?
            when _kind == MilkKind.expressed &&
                !_amountEdited &&
                session.amountMl != null)
          _FromPump(session: session),
        const SizedBox(height: 16),
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
        // All reached from the bottle rather than from the shelf, so every
        // bottle has exactly one tap target and the shelf stays a shelf.
        // Wrapped rather than squeezed: three side by side do not fit a
        // phone at the larger text sizes.
        if (isEdit) ...[
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            children: [
              TextButton.icon(
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
              // Only with something to pour in.
              if (ref.watch(fridgeShelfProvider).length > 1)
                TextButton.icon(
                  icon: const Icon(Icons.merge),
                  label: const Text('Combine'),
                  onPressed: () {
                    // Replaced, as for Split.
                    Navigator.of(context).pop();
                    showCombineSheet(context, bottle: existing);
                  },
                ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _remove(existing),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Takes the bottle off the shelf.
  ///
  /// No confirmation and no undo. Removing is how this screen is *used* — a
  /// bottle comes out of the fridge several times a day — and it is already
  /// two taps, through the bottle's own sheet. No message either: the bottle
  /// leaving the shelf is the confirmation, and a bar saying so would only
  /// cover the shelf it is confirming. Only a failure is worth a word.
  void _remove(FridgeBottle bottle) {
    if (_saving) return;
    final repo = ref.read(fridgeRepositoryProvider);
    if (repo == null) return;
    _saving = true;
    saveAndClose(
      context,
      () => repo.delete(bottle.id),
      failure: 'Could not remove the bottle',
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

  /// Every amount the first bottle can be — see [splitStops].
  late final List<double> _stops = splitStops(widget.bottle.amountMl);

  @override
  void initState() {
    super.initState();
    _firstMl = defaultSplitMl(widget.bottle.amountMl) ?? 0;
  }

  void _split() {
    if (_saving) return;
    final repo = ref.read(fridgeRepositoryProvider);
    if (repo == null) return;
    _saving = true;
    saveAndClose(
      context,
      () => repo.split(widget.bottle, _firstMl),
      failure: 'Could not split the bottle',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final total = widget.bottle.amountMl;
    final rest = total - _firstMl;
    // A bottle too small to divide: not a step for each side.
    final divisible = _stops.isNotEmpty;
    final at = _stops.indexOf(_firstMl);

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
          // Only one way to split it, five and the rest: nothing to slide.
          if (_stops.length > 1)
            Slider(
              // Along the stops rather than a scale of millilitres, so it
              // moves 5 ml at a time like Combine's pour, and the second
              // bottle takes whatever odd amount is left.
              value: at.toDouble(),
              max: (_stops.length - 1).toDouble(),
              divisions: _stops.length - 1,
              label: formatVolume(_firstMl, units),
              onChanged: (v) => setState(() => _firstMl = _stops[v.round()]),
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

/// Pours another bottle into [bottle], which is the one that stays.
///
/// Two at a time: three is two passes, which keeps the list and what it
/// will do simple to read. Shows what the bottle will hold before anything
/// is saved, and saves in one go, so there is no undo — the same as Split
/// and Remove.
Future<void> showCombineSheet(
  BuildContext context, {
  required FridgeBottle bottle,
}) {
  return showAppSheet<void>(context, builder: (_) => _CombineSheet(bottle));
}

class _CombineSheet extends ConsumerStatefulWidget {
  const _CombineSheet(this.bottle);

  final FridgeBottle bottle;

  @override
  ConsumerState<_CombineSheet> createState() => _CombineSheetState();
}

class _CombineSheetState extends ConsumerState<_CombineSheet> {
  /// The bottle picked to pour in, by id: the shelf can change under the
  /// sheet, and a bottle that has gone is no longer picked.
  String? _pouredId;
  bool _saving = false;

  /// How much of the picked bottle to pour in. Set to [defaultPourMl] when
  /// a bottle is picked; null until then.
  double? _pourMl;

  void _pick(FridgeBottle kept, FridgeBottle poured) => setState(() {
    _pouredId = poured.id;
    _pourMl = defaultPourMl(kept, poured);
  });

  void _combine(FridgeBottle kept, FridgeBottle poured, double pourMl) {
    if (_saving) return;
    final repo = ref.read(fridgeRepositoryProvider);
    if (repo == null) return;
    _saving = true;
    saveAndClose(
      context,
      () => repo.combine(kept, poured, pourMl: pourMl),
      failure: 'Could not combine the bottles',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final units = ref.watch(unitSystemProvider);
    final shelf = ref.watch(fridgeShelfProvider);
    // As it is now, in case another phone changed it since the sheet opened.
    final kept = shelf.firstWhere(
      (b) => b.id == widget.bottle.id,
      orElse: () => widget.bottle,
    );
    final others = [
      for (final b in shelf)
        if (b.id != kept.id) b,
    ];
    final poured = others.where((b) => b.id == _pouredId).firstOrNull;
    // Kept within the bottle as it is now, in case it shrank meanwhile.
    final pour = poured == null
        ? null
        : (_pourMl ?? poured.amountMl).clamp(0.0, poured.amountMl);
    final into = poured == null ? null : combined(kept, poured, pourMl: pour);
    final kind = kept.kind.label.toLowerCase();

    String describe(FridgeBottle b) =>
        '${formatVolume(b.amountMl, units)} · ${b.kind.label} · '
        '${b.kind.filledLabel.toLowerCase()} '
        '${FeedingFormat.clockStamp(context, b.filledAt)}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Combine bottles', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Pick a bottle to pour from into this one '
          '(${describe(kept)}), then how much. Only $kind can go in.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final b in others)
          _PourChoice(
            label: describe(b),
            reason: canCombine(kept, b)
                ? null
                : "${b.kind.label} — can't mix with $kind",
            picked: b.id == _pouredId,
            onTap: () => _pick(kept, b),
          ),
        if (poured != null && into != null && pour != null) ...[
          const SizedBox(height: 12),
          _PourAmount(
            pourMl: pour,
            fromMl: poured.amountMl,
            units: units,
            onChanged: (v) => setState(() => _pourMl = v),
          ),
          const SizedBox(height: 8),
          _CombinePreview(
            kept: kept,
            poured: poured,
            pourMl: pour,
            into: into,
            units: units,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: poured == null || pour == null || pour <= 0
              ? null
              : () => _combine(kept, poured, pour),
          child: const Text('Combine'),
        ),
      ],
    );
  }
}

/// One bottle that could be poured in: picked, pickable, or not, with why.
class _PourChoice extends StatelessWidget {
  const _PourChoice({
    required this.label,
    required this.reason,
    required this.picked,
    required this.onTap,
  });

  final String label;

  /// Why it cannot be picked, or null when it can.
  final String? reason;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = reason == null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      selected: picked,
      onTap: enabled ? onTap : null,
      leading: Icon(
        picked ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(label),
      subtitle: enabled ? null : Text(reason!),
    );
  }
}

/// How much of the other bottle to pour in: a slider in steps of
/// [pourStepMl], up to all of it — see [pourStops].
class _PourAmount extends StatelessWidget {
  const _PourAmount({
    required this.pourMl,
    required this.fromMl,
    required this.units,
    required this.onChanged,
  });

  final double pourMl;

  /// What the other bottle holds: as far as the slider goes.
  final double fromMl;
  final UnitSystem units;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Too little to choose an amount from: it all goes in.
    final stops = pourStops(fromMl);
    // Too little to choose an amount from: it all goes in.
    if (stops.length < 2) return const SizedBox.shrink();
    // The stop nearest what is chosen: the slider moves between stops, not
    // along a scale of millilitres.
    var at = 0;
    for (var i = 1; i < stops.length; i++) {
      if ((stops[i] - pourMl).abs() < (stops[at] - pourMl).abs()) at = i;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Pour in', style: theme.textTheme.titleSmall)),
            Text(
              pourMl >= fromMl
                  ? 'All ${formatVolume(fromMl, units)}'
                  : '${formatVolume(pourMl, units)} of '
                        '${formatVolume(fromMl, units)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: at.toDouble(),
          max: (stops.length - 1).toDouble(),
          divisions: stops.length - 1,
          label: formatVolume(stops[at], units),
          onChanged: (v) => onChanged(stops[v.round()]),
        ),
      ],
    );
  }
}

/// What the combined bottle will be, said before it is: "30 ml + 100 ml =
/// 130 ml", the time it keeps, and a warning when it is more than a bottle
/// holds.
class _CombinePreview extends StatelessWidget {
  const _CombinePreview({
    required this.kept,
    required this.poured,
    required this.pourMl,
    required this.into,
    required this.units,
  });

  final FridgeBottle kept;
  final FridgeBottle poured;
  final double pourMl;
  final FridgeBottle into;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final over = into.amountMl > bottleCapacityMl;
    final left = poured.amountMl - pourMl;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatVolume(kept.amountMl, units)} + '
            '${formatVolume(pourMl, units)} = '
            '${formatVolume(into.amountMl, units)} in this bottle',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // What happens to the other one, which is the half of a partial
          // pour that is easy to lose track of.
          Text(
            left > 0
                ? '${formatVolume(left, units)} stays in the other bottle.'
                : 'The other bottle is used up and comes off the shelf.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          // Said, because the shelf goes by this time: the bottle may move
          // to stand with the older milk.
          Text(
            'Keeps the older time, '
            '${FeedingFormat.clockStamp(context, into.filledAt)}, '
            'because the milk is as old as its oldest part.',
            style: theme.textTheme.bodyMedium,
          ),
          if (over) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${formatVolume(into.amountMl, units)} is more than a '
                    '${formatVolume(bottleCapacityMl, units)} bottle holds.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Amount from your 9:05 AM pump", under the time row.
class _FromPump extends StatelessWidget {
  const _FromPump({required this.session});

  final PumpingEvent session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = FeedingFormat.clockStamp(context, session.time);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Amount from your $when pump',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
