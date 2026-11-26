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

/// Midnight at the start of [time]'s local calendar day.
///
/// Used as the family key for [todayEventsProvider] so 30-second ticks within
/// the same day reuse one provider instance, while crossing midnight switches
/// immediately to the new day without waiting for a stream write.
DateTime calendarDay(DateTime time) =>
    DateTime(time.year, time.month, time.day);

/// Everything logged on [day], from the streams Home is already subscribed to.
final todayEventsProvider = Provider.autoDispose.family<TodayEvents, DateTime>((
  ref,
  day,
) {
  bool isSameDay(DateTime t) =>
      t.year == day.year && t.month == day.month && t.day == day.day;

  return (
    feedings: [
      for (final f in ref.watch(recentFeedingsProvider).value ?? const [])
        if (isSameDay(f.startTime)) f,
    ],
    diapers: [
      for (final d in ref.watch(recentDiapersProvider).value ?? const [])
        if (isSameDay(d.time)) d,
    ],
    pumps: [
      for (final p in ref.watch(recentPumpingProvider).value ?? const [])
        if (isSameDay(p.time)) p,
    ],
  );
});

/// Totals for [day], from the same events.
final todayStatsProvider = Provider.autoDispose.family<DayStats, DateTime>((
  ref,
  day,
) {
  final today = ref.watch(todayEventsProvider(day));
  return DayStats.from(today.feedings, today.diapers, pumps: today.pumps);
});
