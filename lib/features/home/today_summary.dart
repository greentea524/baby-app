import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../timeline/day_stats.dart';
import '../timeline/timeline_format.dart';

/// How today is going so far (KAN-183).
///
/// Derived from the recent streams Home already subscribes to rather than
/// three more per-day queries — the recent lists hold the last 50 of each, so
/// they comfortably cover one day, and filtering client-side means the
/// figures move the instant something is logged.
///
/// Deliberately not built on `selectedDayProvider`: that follows whatever day
/// the timeline is browsing, so Home would quietly start reporting last
/// Tuesday.
typedef TodayEvents = ({
  List<FeedingEvent> feedings,
  List<DiaperEvent> diapers,
  List<PumpingEvent> pumps,
});

/// Everything logged today, from the streams Home is already subscribed to.
final todayEventsProvider = Provider<TodayEvents>((ref) {
  final now = DateTime.now();
  bool isToday(DateTime t) =>
      t.year == now.year && t.month == now.month && t.day == now.day;

  return (
    feedings: [
      for (final f in ref.watch(recentFeedingsProvider).value ?? const [])
        if (isToday(f.startTime)) f,
    ],
    diapers: [
      for (final d in ref.watch(recentDiapersProvider).value ?? const [])
        if (isToday(d.time)) d,
    ],
    pumps: [
      for (final p in ref.watch(recentPumpingProvider).value ?? const [])
        if (isToday(p.time)) p,
    ],
  );
});

/// Today's totals, from the same events.
final todayStatsProvider = Provider<DayStats>((ref) {
  final today = ref.watch(todayEventsProvider);
  return DayStats.from(today.feedings, today.diapers, pumps: today.pumps);
});

/// Today's running totals as a single line.
///
/// One row rather than a wrapping grid of chips: this is a glanceable
/// footnote to the cards above, not a section in its own right, and letting
/// it reflow to two rows made it compete with them for attention.
class TodaySummaryRow extends ConsumerWidget {
  const TodaySummaryRow({super.key, this.showCounts = true});

  /// False when the day charts are on screen below.
  ///
  /// Their legend already says how many feeds and diapers there were, and
  /// the diaper bar breaks them down further — repeating the numbers a
  /// centimetre above is a second answer to a question already answered.
  /// The volumes stay either way: no legend carries millilitres.
  final bool showCounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(todayStatsProvider);
    final units = ref.watch(unitSystemProvider);
    final theme = Theme.of(context);

    final parts = <({IconData icon, String text})>[
      if (showCounts) ...[
        (icon: Icons.restaurant, text: '${stats.feedCount} feeds'),
        (
          icon: Icons.baby_changing_station,
          text: '${stats.diaperCount} diapers',
        ),
      ],
      if (stats.bottleMl > 0)
        (
          icon: Icons.local_drink,
          text: units.isMetric
              ? '${TimelineFormat.ml(stats.bottleMl)} ml'
              : '${formatFlOz(stats.bottleMl)} fl oz',
        ),
      if (stats.breastMinutes > 0)
        (icon: Icons.child_friendly, text: '${stats.breastMinutes} min'),
      if (stats.pumpCount > 0)
        (
          icon: Icons.opacity,
          text: units.isMetric
              ? '${TimelineFormat.ml(stats.pumpedMl)} ml'
              : '${formatFlOz(stats.pumpedMl)} fl oz',
        ),
    ];

    // A row of zeros is noise on a dashboard, and so is a row of nothing:
    // with the counts moved to the chart legend, a day of breastfeeding and
    // no bottles leaves this with nothing to say.
    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      // Scrolls rather than wraps, so it stays one line however many figures
      // there are. Bottle and pumping only appear when they have a value, so
      // it rarely needs to.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'Today',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            for (final part in parts) ...[
              Icon(part.icon, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Text(part.text, style: theme.textTheme.bodyMedium),
              const SizedBox(width: 14),
            ],
          ],
        ),
      ),
    );
  }
}
