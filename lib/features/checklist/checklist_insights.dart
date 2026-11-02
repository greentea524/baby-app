import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/daily_check.dart';
import '../../data/repositories/repository_providers.dart';
import 'checklist_logic.dart';
import 'daily_checklist.dart';
import 'timed_item_sheet.dart';

/// The daily checklist in Insights: for each item, how it went over the
/// range being looked at — days done, the average day, the current and best
/// streaks, and a square per day.
///
/// For a single day, how far today has got instead of a strip of one.
///
/// Reads a year back, as the streaks sheet does, so a best streak is a
/// year's best; Home's own read is today's alone.
class ChecklistInsights extends ConsumerWidget {
  const ChecklistInsights({super.key, required this.days, required this.now});

  /// How many days the range covers, ending today.
  final int days;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(currentBabyProvider)?.checklist ?? const [];
    final checks =
        ref
            .watch(
              checksSinceProvider(
                daysBefore(dayOf(now), streakHistoryDays - 1),
              ),
            )
            .value ??
        const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          _ItemInsight(item: item, checks: checks, days: days, now: now),
      ],
    );
  }
}

class _ItemInsight extends StatelessWidget {
  const _ItemInsight({
    required this.item,
    required this.checks,
    required this.days,
    required this.now,
  });

  final ChecklistItem item;
  final List<DailyCheck> checks;
  final int days;
  final DateTime now;

  /// "24 min", "3.2 times", "1 time": an average day's amount.
  String _amount(double v) {
    if (item.timed) return minutesLabel(v.round());
    final shown = v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
    return '$shown ${v == 1 ? 'time' : 'times'}';
  }

  /// How far today has got: "Done", "15 of 30 min", "2 of 5", "Not yet".
  String _today(int amount) {
    if (amount >= item.goal) return 'Done today';
    if (amount == 0) return 'Not done yet today';
    return item.timed
        ? '${minutesLabel(amount)} of ${minutesLabel(item.goal)} today'
        : '$amount of ${item.goal} today';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final current = streak(checks, item, now);
    final best = bestStreak(checks, item);
    final summary = rangeSummary(checks, item, now, count: days);
    final shares = recentDays(checks, item, now, count: days);
    final todayAmount = progressOn(checks, [item], now)[item.id] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(checklistIcon(item.icon), color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: theme.textTheme.titleSmall),
                Text(
                  days == 1
                      ? _today(todayAmount)
                      : [
                          'Done ${summary.doneDays} of $days days',
                          // Only where a day is more than done-or-not.
                          if (item.goal > 1)
                            '${_amount(summary.perDay)} a day on average',
                        ].join(' · '),
                  key: ValueKey('insight-${item.id}'),
                  style: muted,
                ),
                Text(
                  [
                    current == 0
                        ? 'No streak now'
                        : 'Streak $current ${current == 1 ? 'day' : 'days'}',
                    if (best > 0) 'best $best ${best == 1 ? 'day' : 'days'}',
                  ].join(' · '),
                  key: ValueKey('streaks-${item.id}'),
                  style: muted,
                ),
                if (days > 1) ...[
                  const SizedBox(height: 6),
                  _DayStrip(shares: shares, done: summary.doneDays),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A square per day of the range, oldest first, ending today: filled for
/// done, tinted for part done, empty for none.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.shares, required this.done});

  final List<double> shares;
  final int done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A week's squares can be big; a month's have to share the width.
    final height = shares.length <= 7 ? 22.0 : 14.0;
    return Semantics(
      label: 'Done $done of the last ${shares.length} days',
      excludeSemantics: true,
      child: Row(
        children: [
          for (final (i, share) in shares.indexed) ...[
            if (i > 0) SizedBox(width: shares.length <= 7 ? 4 : 2),
            Expanded(
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: share >= 1
                      ? scheme.primary
                      : share > 0
                      ? scheme.primary.withValues(alpha: 0.3)
                      : scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
