import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/daily_check.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import 'checklist_logic.dart';
import 'daily_checklist.dart';
import 'timed_item_sheet.dart';

/// Opens [day] on the checklist to be put right: a bath that was given and
/// never ticked, a vitamin ticked on the wrong day.
Future<void> showChecklistDaySheet(
  BuildContext context, {
  required DateTime day,
  DateTime? now,
}) => showAppSheet<void>(
  context,
  builder: (_) =>
      ChecklistDaySheet(day: dayOf(day), now: now ?? DateTime.now()),
);

/// Every checklist item for one day, each with what it takes to correct it:
/// a switch for something done once, a count for several times, minutes
/// for something timed.
///
/// What is added here is dated the day it is for — at the time of day now,
/// for today; at noon for a day gone by, which keeps it clear of midnight
/// on either side.
class ChecklistDaySheet extends ConsumerWidget {
  const ChecklistDaySheet({super.key, required this.day, required this.now});

  /// Midnight at the start of the day.
  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final items = ref.watch(currentBabyProvider)?.checklist ?? const [];
    // The streaks sheet's own read, so what is shown here is already there.
    final checks =
        ref
            .watch(
              checksSinceProvider(
                daysBefore(dayOf(now), streakHistoryDays - 1),
              ),
            )
            .value ??
        const [];
    final isToday = day == dayOf(now);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isToday ? 'Today' : local.formatFullDate(day),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Put right what was done this day.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _DayItem(
            item: item,
            ticks: ticksOf(checks, item.id, day)
              ..sort((a, b) => a.time.compareTo(b.time)),
            at: isToday ? now : DateTime(day.year, day.month, day.day, 12),
          ),
        ],
      ],
    );
  }
}

class _DayItem extends ConsumerWidget {
  const _DayItem({required this.item, required this.ticks, required this.at});

  final ChecklistItem item;

  /// The day's ticks of [item], earliest first.
  final List<DailyCheck> ticks;

  /// When anything added here is dated.
  final DateTime at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amount = ticks.fold<int>(0, (sum, c) => sum + amountOf(item, c));
    final done = amount >= item.goal;
    final repo = ref.read(checksRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    void failed(Object e) => messenger.showSnackBar(
      SnackBar(content: Text('Could not save ${item.label}: $e')),
    );

    // Not waited on, as everywhere else: offline the write would not finish
    // until the phone reconnects, and the local cache shows it at once.
    void add({int? minutes}) {
      if (repo == null) return;
      try {
        unawaited(
          repo
              .addNow(
                DailyCheck(
                  id: '',
                  itemId: item.id,
                  time: at,
                  label: item.label,
                  minutes: minutes,
                ),
              )
              .written
              .catchError(failed),
        );
      } catch (e) {
        failed(e);
      }
    }

    void remove(Iterable<DailyCheck> gone) {
      if (repo == null) return;
      for (final c in gone) {
        unawaited(Future.sync(() => repo.delete(c.id)).catchError(failed));
      }
    }

    final status = item.timed
        ? '${minutesLabel(amount)} of ${minutesLabel(item.goal)}'
        : item.perDay > 1
        ? '$amount of ${item.goal}'
        : done
        ? 'Done'
        : 'Not done';

    final Widget control;
    if (!item.timed && item.perDay == 1) {
      control = Switch(
        key: ValueKey('day-switch-${item.id}'),
        value: done,
        onChanged: (on) => on ? add() : remove(ticks),
      );
    } else if (!item.timed) {
      control = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'One fewer',
            icon: const Icon(Icons.remove),
            onPressed: ticks.isEmpty ? null : () => remove([ticks.last]),
          ),
          IconButton(
            tooltip: 'One more',
            icon: const Icon(Icons.add),
            onPressed: amount >= item.goal ? null : add,
          ),
        ],
      );
    } else {
      control = IconButton(
        tooltip: 'Take the last one back',
        icon: const Icon(Icons.undo),
        onPressed: ticks.isEmpty ? null : () => remove([ticks.last]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : checklistIcon(item.icon),
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: theme.textTheme.titleMedium),
                    Text(
                      status,
                      key: ValueKey('day-status-${item.id}'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              control,
            ],
          ),
          if (item.timed)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in quickMinutes)
                    ActionChip(
                      key: ValueKey('day-add-${item.id}-$m'),
                      avatar: const Icon(Icons.add),
                      label: Text('$m min'),
                      onPressed: () => add(minutes: m),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
