import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/feeding_event.dart';
import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import 'range_stats.dart';

/// How far back the insights trends look (KAN-166).
enum InsightsRange {
  week('Week', 7),
  month('Month', 30);

  const InsightsRange(this.label, this.days);

  final String label;
  final int days;
}

/// What the insights screen needs for a range: the daily aggregates, plus the
/// feeds they were derived from.
///
/// The raw events are carried alongside rather than discarded because the
/// feed-times chart needs the exact timestamps that aggregation throws away —
/// and re-fetching them would be a second identical query (KAN-185).
typedef InsightsData = ({RangeStats stats, List<FeedingEvent> feedings});

/// Aggregated trends for [range], ending with today. One-shot fetches rather
/// than live streams: a month of events is a lot to keep subscribed, and the
/// screen is a review view, not a logging surface.
///
/// Null when no baby is selected, so the UI can show the empty prompt.
final rangeStatsProvider = FutureProvider.family<InsightsData?, InsightsRange>((
  ref,
  range,
) async {
  final feedingRepo = ref.watch(feedingRepositoryProvider);
  final diaperRepo = ref.watch(diaperRepositoryProvider);
  final pumpingRepo = ref.watch(pumpingRepositoryProvider);
  if (feedingRepo == null || diaperRepo == null) return null;

  final now = DateTime.now();
  // End is exclusive and covers all of today.
  final end = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));
  final start = end.subtract(Duration(days: range.days));

  final feedings = await feedingRepo.fetchRange(start, end);
  final diapers = await diaperRepo.fetchRange(start, end);
  final pumps = pumpingRepo == null
      ? const <PumpingEvent>[]
      : await pumpingRepo.fetchRange(start, end);

  return (
    stats: RangeStats.from(
      start: start,
      end: end,
      feedings: feedings,
      diapers: diapers,
      pumps: pumps,
    ),
    feedings: feedings,
  );
});
