import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../timeline/day_stats.dart';

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
