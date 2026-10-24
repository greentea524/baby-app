import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/models/daily_check.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/action_snack_bar.dart';
import '../common/app_sheet.dart';
import '../feeding/feeding_format.dart';
import 'checklist_logic.dart';
import 'checklist_settings_screen.dart';

/// Today's checklist on Home: each item as a chip, ticked once it is done.
///
/// One tap ticks, and says so with an undo, because a tick a caregiver did
/// not mean is a vitamin the other one then skips. Tapping a ticked item
/// says when it was done and by whom — the question two caregivers sharing
/// a baby actually have — with the way to untick it.
///
/// Not there at all until someone adds an item in Settings.
class DailyChecklistCard extends ConsumerWidget {
  const DailyChecklistCard({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(currentBabyProvider)?.checklist ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dayOf(now);
    final checks = ref.watch(checksSinceProvider(today)).value ?? const [];
    final done = ticksOn(checks, today);
    final count = items.where((i) => done.containsKey(i.id)).length;
    final allDone = count == items.length;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (allDone) ...[
                  Icon(Icons.check_circle, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    allDone
                        ? 'DAILY · ALL DONE TODAY'
                        : 'DAILY · $count OF ${items.length}',
                    key: const ValueKey('checklist-progress'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: allDone ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Streaks',
                  icon: const Icon(Icons.local_fire_department_outlined),
                  onPressed: () => showChecklistStreaks(context, now: now),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in items)
                    FilterChip(
                      key: ValueKey('check-${item.id}'),
                      selected: done.containsKey(item.id),
                      // The item's own picture until it is done, then the
                      // tick in its place.
                      avatar: done.containsKey(item.id)
                          ? null
                          : Icon(checklistIcon(item.icon)),
                      label: Text(item.label),
                      onSelected: (_) => done[item.id] == null
                          ? tickItem(context, ref, item)
                          : _showTick(context, ref, item, done[item.id]!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTick(
    BuildContext context,
    WidgetRef ref,
    ChecklistItem item,
    DailyCheck tick,
  ) {
    showTickDetails(
      context,
      label: item.label,
      tick: tick,
      now: now,
      onUntick: () => untickItem(ref, item, now),
    );
  }
}

/// What a tick is called in the activity log: the item's name on the list
/// now, so a rename shows everywhere, or else the name it was ticked under.
String checkLabel(DailyCheck tick, List<ChecklistItem> items) {
  for (final item in items) {
    if (item.id == tick.itemId) return item.label;
  }
  final saved = tick.label?.trim();
  return saved == null || saved.isEmpty ? 'Checklist item' : saved;
}

/// The picture for a tick in the activity log: its item's, while the item
/// is still on the list.
IconData checkIcon(DailyCheck tick, List<ChecklistItem> items) {
  for (final item in items) {
    if (item.id == tick.itemId) return checklistIcon(item.icon);
  }
  return checklistIcon(ChecklistIcon.other);
}

/// Opens the sheet saying when [tick] was done and by whom, with a way to
/// take it back. [onUntick] runs once the sheet has closed.
Future<void> showTickDetails(
  BuildContext context, {
  required String label,
  required DailyCheck tick,
  required VoidCallback onUntick,
  DateTime? now,
}) => showAppSheet<void>(
  context,
  builder: (sheet) => _TickDetails(
    label: label,
    tick: tick,
    now: now ?? DateTime.now(),
    onUntick: () {
      Navigator.pop(sheet);
      onUntick();
    },
  ),
);

/// What to call the caregiver signed in here, as a dose of medicine does.
String? _myName(WidgetRef ref) {
  final user = ref.read(authStateProvider).value;
  final name = user?.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return user?.email?.split('@').first;
}

/// Ticks [item] off as done now, with an undo.
///
/// The write is not waited on: offline it would not finish until the phone
/// reconnects, and the tick shows straight away from the local cache. The
/// undo deletes that one tick by its id, so it still works after Home has
/// gone from the screen.
void tickItem(BuildContext context, WidgetRef ref, ChecklistItem item) {
  final repo = ref.read(checksRepositoryProvider);
  if (repo == null) return;
  final messenger = ScaffoldMessenger.of(context);
  void failed(Object e) => messenger.showSnackBar(
    SnackBar(content: Text('Could not save ${item.label}: $e')),
  );

  final ({String id, Future<void> written}) tick;
  try {
    tick = repo.addNow(
      DailyCheck(
        id: '',
        itemId: item.id,
        time: DateTime.now(),
        label: item.label,
        byName: _myName(ref),
      ),
    );
  } catch (e) {
    failed(e);
    return;
  }
  unawaited(tick.written.catchError(failed));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      actionSnackBar(
        content: Text('${item.label} done'),
        actionLabel: 'Undo',
        onAction: () => unawaited(
          Future.sync(() => repo.delete(tick.id)).catchError(failed),
        ),
      ),
    );
}

/// Unticks [item] for [day]: every tick of it that day, in case two
/// caregivers both ticked it.
void untickItem(WidgetRef ref, ChecklistItem item, DateTime day) {
  final repo = ref.read(checksRepositoryProvider);
  if (repo == null) return;
  final checks = ref.read(checksSinceProvider(dayOf(day))).value ?? const [];
  for (final c in ticksOf(checks, item.id, day)) {
    unawaited(Future.sync(() => repo.delete(c.id)).catchError((_) {}));
  }
}

class _TickDetails extends ConsumerWidget {
  const _TickDetails({
    required this.label,
    required this.tick,
    required this.now,
    required this.onUntick,
  });

  final String label;
  final DailyCheck tick;
  final DateTime now;
  final VoidCallback onUntick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(authStateProvider).value?.uid;
    final by = tick.createdBy != null && tick.createdBy == me
        ? 'you'
        : tick.byName?.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.titleLarge)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          [
            'Done ${FeedingFormat.clockStamp(context, tick.time, now: now)}',
            if (by != null && by.isNotEmpty) 'by $by',
          ].join(' '),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.undo),
          label: const Text('Not done — untick it'),
          onPressed: onUntick,
        ),
      ],
    );
  }
}

/// How far back the streaks sheet reads: a year, which is as long as a
/// streak it can show.
const streakHistoryDays = 366;

/// Opens the streaks sheet: each item's run of days, and its last week.
Future<void> showChecklistStreaks(BuildContext context, {DateTime? now}) =>
    showAppSheet<void>(
      context,
      builder: (_) => ChecklistStreaks(
        now: now,
        onEdit: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ChecklistSettingsScreen(),
          ),
        ),
      ),
    );

/// Each item's streak — days in a row it has been done — and a dot for each
/// of the last seven days.
///
/// The achievement half of the checklist, kept off Home so the strip stays
/// one line. A missed day just starts the count again: nothing here scolds.
class ChecklistStreaks extends ConsumerWidget {
  const ChecklistStreaks({super.key, this.now, this.onEdit});

  final DateTime? now;

  /// Opens the list's settings. Null hides the button.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clock = now ?? DateTime.now();
    final items = ref.watch(currentBabyProvider)?.checklist ?? const [];
    final checks =
        ref
            .watch(
              checksSinceProvider(
                daysBefore(dayOf(clock), streakHistoryDays - 1),
              ),
            )
            .value ??
        const [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Streaks', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Days in a row, and the last week ending today.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in items)
          _StreakRow(
            item: item,
            streak: streak(checks, item.id, clock),
            week: recentDays(checks, item.id, clock),
          ),
        if (onEdit case final edit?) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit the list'),
              onPressed: () {
                Navigator.pop(context);
                edit();
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({
    required this.item,
    required this.streak,
    required this.week,
  });

  final ChecklistItem item;
  final int streak;
  final List<bool> week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hot = streak >= 2;
    // Warm, as a flame is, rather than the theme's own accent, which with
    // most seeds came out a cool blue-grey. Deep enough in the light theme
    // to read as text, light enough in the dark one.
    final flame = theme.brightness == Brightness.dark
        ? const Color(0xFFFFA94D)
        : const Color(0xFFC2410C);
    final doneInWeek = week.where((d) => d).length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(checklistIcon(item.icon), color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    if (hot) ...[
                      Icon(Icons.local_fire_department, size: 16, color: flame),
                      const SizedBox(width: 2),
                    ],
                    Flexible(
                      child: Text(
                        streakLabel(streak),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: hot ? flame : scheme.onSurfaceVariant,
                          fontWeight: hot ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Done $doneInWeek of the last ${week.length} days',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, on) in week.indexed)
                  Container(
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? scheme.primary : null,
                      border: on
                          ? null
                          : Border.all(
                              color: scheme.outlineVariant,
                              width: 1.5,
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "12 days in a row", "1 day", "No streak yet".
String streakLabel(int days) => switch (days) {
  0 => 'No streak yet',
  1 => '1 day',
  _ => '$days days in a row',
};
