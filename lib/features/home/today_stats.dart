import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../timeline/day_stats.dart';

/// How today is going so far (KAN-183), for the Home dashboard.
///
/// Derived from the recent streams Home already subscribes to, rather than
/// three more per-day queries. The recent lists hold the last 50 of each, so
/// they comfortably cover a single day, and filtering client-side means the
/// figures update the instant something is logged.
///
/// Deliberately not built on `selectedDayProvider`: that follows whatever day
/// the timeline is browsing, so Home would quietly start reporting last
/// Tuesday.
final todayStatsProvider = Provider<DayStats>((ref) {
  final now = DateTime.now();
  bool isToday(DateTime t) =>
      t.year == now.year && t.month == now.month && t.day == now.day;

  final feeds = (ref.watch(recentFeedingsProvider).value ?? const [])
      .where((f) => isToday(f.startTime))
      .toList();
  final diapers = (ref.watch(recentDiapersProvider).value ?? const [])
      .where((d) => isToday(d.time))
      .toList();
  final pumps = (ref.watch(recentPumpingProvider).value ?? const [])
      .where((p) => isToday(p.time))
      .toList();

  return DayStats.from(feeds, diapers, pumps: pumps);
});
