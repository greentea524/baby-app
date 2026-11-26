import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/volume_entry.dart';
import '../../core/layout/app_bar_room.dart';
import '../../core/format/volume_format.dart';
import '../../core/format/unit_system.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/care_stay.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/milk_kind.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import '../common/save_and_close.dart';
import '../common/volume_field.dart';
import '../feeding/feeding_quick_log.dart';
import '../reminders/reminder_providers.dart';
import 'auto_feed.dart';

/// Who usually has the baby, offered as one tap each.
const carerChoices = ['Grandparents', 'Sitter', 'Daycare'];

const _lastCarerKey = 'last_carer';

/// The icon for a baby in someone else's care.
const awayIcon = Icons.directions_car_outlined;

/// Opens the drop-off form.
Future<void> showDropOffSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _DropOffSheet());

class _DropOffSheet extends ConsumerStatefulWidget {
  const _DropOffSheet();

  @override
  ConsumerState<_DropOffSheet> createState() => _DropOffSheetState();
}

class _DropOffSheetState extends ConsumerState<_DropOffSheet> {
  final _carer = TextEditingController();
  final _amount = TextEditingController();
  late DateTime _time;
  late VolumeUnit _unit;
  late MilkKind _milk;
  bool _autoFeed = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _time = DateTime.now();
    _unit = VolumeUnit.initial;
    _carer.text =
        ref.read(sharedPreferencesProvider).getString(_lastCarerKey) ??
        carerChoices.first;
    // The usual bottle: the last one fed, its amount and its milk.
    final feeds = ref.read(recentFeedingsProvider).value ?? const [];
    FeedingEvent? lastBottle;
    for (final f in feeds) {
      if (f.type == FeedingType.bottle && f.amountMl != null && !f.isSnack) {
        lastBottle = f;
        break;
      }
    }
    _milk = lastBottle?.milk ?? MilkKind.expressed;
    if (lastBottle?.amountMl case final ml?) {
      _amount.text = _unit.fieldText(ml);
    }
  }

  @override
  void dispose() {
    _carer.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    if (_saving) return;
    final repo = ref.read(staysRepositoryProvider);
    if (repo == null) return;
    final carer = _carer.text.trim();
    final interval = ref.read(reminderSettingsProvider).intervalMinutes;
    final stay = CareStay(
      id: '',
      droppedAt: _time,
      carer: carer.length > 60 ? carer.substring(0, 60) : carer,
      autoFeed: _autoFeed,
      amountMl: _autoFeed
          ? resolveAmountMl(
              typed: double.tryParse(_amount.text.trim()),
              unit: _unit,
              storedMl: null,
              edited: true,
            )
          : null,
      milk: _autoFeed ? _milk : null,
      intervalMinutes: interval.clamp(30, 720),
    );
    unawaited(
      ref.read(sharedPreferencesProvider).setString(_lastCarerKey, carer),
    );
    final messenger = ScaffoldMessenger.of(context);
    _saving = true;
    saveAndClose(context, () {
      final added = repo.addNow(stay);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            carer.isEmpty ? 'Dropped off' : 'Dropped off with $carer',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(repo.delete(added.id)),
          ),
        ),
      );
      return added.written;
    }, failure: 'Could not log the drop-off');
  }

  @override
  Widget build(BuildContext context) {
    final interval = ref.watch(reminderSettingsProvider).intervalMinutes;
    final hours = interval ~/ 60;
    final minutes = interval % 60;
    final every = [if (hours > 0) '${hours}h', if (minutes > 0) '${minutes}m'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Drop off', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Text('Who has the baby', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in carerChoices)
              ChoiceChip(
                label: Text(c),
                selected: _carer.text.trim() == c,
                onSelected: (_) => setState(() => _carer.text = c),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _carer,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Or someone else',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        EventTimeRow(time: _time, onChanged: (t) => setState(() => _time = t)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Log feeds automatically'),
          subtitle: Text(
            'A feed every ${every.join(' ')}, at each due time, until pick-up',
          ),
          value: _autoFeed,
          onChanged: (v) => setState(() => _autoFeed = v),
        ),
        if (_autoFeed) ...[
          const SizedBox(height: 8),
          SegmentedButton<MilkKind>(
            segments: [
              for (final k in MilkKind.values)
                ButtonSegment(value: k, label: Text(k.label)),
            ],
            selected: {_milk},
            onSelectionChanged: (s) => setState(() => _milk = s.first),
          ),
          const SizedBox(height: 12),
          VolumeField(
            controller: _amount,
            unit: _unit,
            label: 'Each feed',
            onUnitChanged: (unit, text) => setState(() {
              _unit = unit;
              _amount.text = text;
            }),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: isFutureLogTime(_time) ? null : _save,
          icon: const Icon(awayIcon),
          label: const Text('Drop off'),
        ),
      ],
    );
  }
}

/// The way into [showDropOffSheet], for Home's header. Nothing while the
/// baby is already away: the banner has the pick-up then.
class DropOffButton extends ConsumerWidget {
  const DropOffButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(activeStayProvider) != null) return const SizedBox.shrink();
    // Exactly what the header set aside for it, scaled down to fit at a
    // large text size rather than taking room from the baby's name.
    return SizedBox(
      width: AppBarRoom.dropOffWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: FilledButton.tonalIcon(
            key: const ValueKey('drop-off'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: () => showDropOffSheet(context),
            icon: const Icon(awayIcon, size: 16),
            label: const Text('Drop off'),
          ),
        ),
      ),
    );
  }
}

/// "With Grandparents since 8:10 AM", with the pick-up, while the baby is
/// away. Nothing otherwise.
///
/// On Home over the status card, and on the nursery screen under its
/// header, so whoever is at the tablet sees it too.
class AwayBanner extends ConsumerWidget {
  const AwayBanner({super.key, this.now, this.margin});

  final DateTime? now;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stay = ref.watch(activeStayProvider);
    if (stay == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final since = TimeOfDay.fromDateTime(stay.droppedAt).format(context);
    final who = stay.carer.trim();
    final units = ref.watch(unitSystemProvider);
    final feeds = !stay.autoFeed
        ? 'Feeds are not logged automatically'
        : stay.amountMl == null
        ? 'Feeds logged automatically'
        : 'Feeds logged automatically · '
              '${formatVolume(stay.amountMl!, units)} each';
    return Container(
      key: const ValueKey('away-banner'),
      margin: margin ?? const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(awayIcon, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  who.isEmpty ? 'Away since $since' : 'With $who since $since',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  feeds,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('picked-up'),
            onPressed: () => pickUp(context, ref, stay),
            child: const Text('Picked up'),
          ),
        ],
      ),
    );
  }
}

/// Ends [stay]: fills in its last automatic feeds up to now, marks it picked
/// up, and shows what was logged while away so it can be put right.
Future<void> pickUp(
  BuildContext context,
  WidgetRef ref,
  CareStay stay, {
  DateTime? now,
}) async {
  final repo = ref.read(staysRepositoryProvider);
  if (repo == null) return;
  final at = now ?? DateTime.now();
  // The feeds due up to now, before the stay closes. Best effort and brief:
  // offline it gives up, and the stay's own record still says where the
  // automatic feeds got to.
  await ref
      .read(autoFeederProvider)
      .run(until: at, stay: stay)
      .timeout(const Duration(seconds: 5), onTimeout: () => 0);
  final closed = stay.copyWith(pickedUpAt: at);
  unawaited(repo.setPickedUp(stay.id, at).catchError((_) {}));
  if (!context.mounted) return;
  await showStaySheet(context, closed);
}

/// What was logged automatically during [stay], each feed a tap from being
/// corrected: after a pick-up, and from the stay's entries in the activity
/// list.
Future<void> showStaySheet(BuildContext context, CareStay stay) =>
    showAppSheet<void>(context, builder: (_) => _StaySheet(stay: stay));

class _StaySheet extends ConsumerStatefulWidget {
  const _StaySheet({required this.stay});

  final CareStay stay;

  @override
  ConsumerState<_StaySheet> createState() => _StaySheetState();
}

/// What was logged while away, put right in as few taps as the carer's
/// account takes: one amount for every feed ("they all had 150"), a nudge
/// on one ("the last was only 90"), a feed that did not happen removed, and
/// one given between due times added.
class _StaySheetState extends ConsumerState<_StaySheet> {
  final _all = TextEditingController();
  late VolumeUnit _unit;

  CareStay get stay => widget.stay;

  @override
  void initState() {
    super.initState();
    _unit = VolumeUnit.initial;
    if (stay.amountMl case final ml?) _all.text = _unit.fieldText(ml);
  }

  @override
  void dispose() {
    _all.dispose();
    super.dispose();
  }

  void _write(FeedingEvent feed) {
    final repo = ref.read(feedingRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      repo.update(feed).catchError((Object e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not change the feed: $e')),
        );
      }),
    );
  }

  void _setAll(List<FeedingEvent> feeds) {
    final ml = resolveAmountMl(
      typed: double.tryParse(_all.text.trim()),
      unit: _unit,
      storedMl: null,
      edited: true,
    );
    if (ml == null || ml <= 0) return;
    for (final f in feeds) {
      if (f.amountMl != ml) _write(withAmount(f, ml));
    }
    FocusScope.of(context).unfocus();
  }

  /// Feeds taken out from this sheet, kept on it with an undo. A snack bar
  /// would sit behind the sheet, out of reach.
  final _removed = <FeedingEvent>[];

  void _remove(FeedingEvent feed) {
    final repo = ref.read(feedingRepositoryProvider);
    if (repo == null) return;
    unawaited(repo.delete(feed.id));
    setState(() => _removed.add(feed));
  }

  void _undoRemove(FeedingEvent feed) {
    final repo = ref.read(feedingRepositoryProvider);
    if (repo == null) return;
    // Put back under its own id, so the stay still knows it.
    unawaited(repo.putBack(feed));
    setState(() => _removed.remove(feed));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final feeds =
        (ref.watch(recentFeedingsProvider).value ?? const <FeedingEvent>[])
            .where((f) => f.id.startsWith(stay.autoFeedPrefix))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final who = stay.carer.trim();
    final step = autoFeedStepMl(units);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          stay.isActive ? (who.isEmpty ? 'Away' : 'With $who') : 'Picked up',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          feeds.isEmpty
              ? 'No feeds ${stay.isActive ? 'have been' : 'were'} logged '
                    'automatically${who.isEmpty ? '' : ' while with $who'}.'
              : '${feeds.length} ${feeds.length == 1 ? 'feed' : 'feeds'} '
                    '${stay.isActive ? 'logged so far' : 'logged automatically'}'
                    '${who.isEmpty ? '' : ' while with $who'}. '
                    'Put them right if the day went differently.',
          style: theme.textTheme.bodyMedium,
        ),
        if (feeds.length > 1) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: VolumeField(
                  key: const ValueKey('set-all-amount'),
                  controller: _all,
                  unit: _unit,
                  label: 'Every feed',
                  onUnitChanged: (unit, text) => setState(() {
                    _unit = unit;
                    _all.text = text;
                  }),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const ValueKey('set-all'),
            onPressed: () => _setAll(feeds),
            child: Text('Set all ${feeds.length} feeds'),
          ),
        ],
        const SizedBox(height: 8),
        for (final f in _removed)
          if (!feeds.any((g) => g.id == f.id))
            ListTile(
              key: ValueKey('removed-${f.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                TimeOfDay.fromDateTime(f.startTime).format(context),
                style: const TextStyle(decoration: TextDecoration.lineThrough),
              ),
              subtitle: const Text('Removed'),
              trailing: TextButton(
                onPressed: () => _undoRemove(f),
                child: const Text('Undo'),
              ),
            ),
        for (final f in feeds)
          ListTile(
            key: ValueKey('auto-${f.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(TimeOfDay.fromDateTime(f.startTime).format(context)),
            subtitle: Text(
              [
                if (f.milk != null) f.milk!.label,
                f.amountMl == null
                    ? 'No amount'
                    : formatVolume(f.amountMl!, units),
              ].join(' · '),
            ),
            onTap: () => showFeedingQuickLog(context, existing: f),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Less',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: (f.amountMl ?? 0) - step <= 0
                      ? null
                      : () => _write(withAmount(f, f.amountMl! - step)),
                ),
                IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () =>
                      _write(withAmount(f, (f.amountMl ?? 0) + step)),
                ),
                IconButton(
                  tooltip: 'Did not happen',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(f),
                ),
              ],
            ),
          ),
        TextButton.icon(
          key: const ValueKey('add-away-feed'),
          onPressed: () =>
              showFeedingQuickLog(context, type: FeedingType.bottle),
          icon: const Icon(Icons.add),
          label: const Text('Add a feed they gave'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
        if (!stay.isActive)
          TextButton(
            onPressed: () {
              final repo = ref.read(staysRepositoryProvider);
              if (repo != null) {
                unawaited(repo.setPickedUp(stay.id, null));
              }
              Navigator.of(context).pop();
            },
            child: const Text('Not picked up yet? Undo'),
          ),
      ],
    );
  }
}
