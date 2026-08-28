import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/pumping_event.dart';
import '../timeline/day_stats.dart';

/// One day's aggregate within a trend range.
typedef TrendPoint = ({DateTime day, DayStats stats});

/// Aggregates a date window into a *dense* per-day series plus range totals,
/// for the insights trends (KAN-166).
///
/// Unlike the export's `ReportSummary`, every day in the window gets a row —
/// including days with no activity — so a trend chart shows real gaps as
/// zeros instead of silently collapsing them.
class RangeStats {
  const RangeStats({
    required this.days,
    required this.totalFeeds,
    required this.totalDiapers,
    required this.totalBottleMl,
    required this.totalBreastMinutes,
    required this.totalPumpedMl,
    required this.totalSnacks,
    required this.totalPumps,
    required this.avgFeedIntervalMinutes,
    required this.feedsPerDay,
    required this.diapersPerDay,
  });

  /// One row per calendar day in the window, earliest first.
  final List<TrendPoint> days;

  final int totalFeeds;
  final int totalDiapers;
  final double totalBottleMl;
  final int totalBreastMinutes;
  final double totalPumpedMl;

  /// Top-ups, kept out of [totalFeeds] and counted here instead — the same
  /// distinction the export makes, so a feeds-per-day figure is not quietly
  /// inflated by them. Their volume still counts toward [totalBottleMl].
  final int totalSnacks;

  /// How many pump sessions, as against how much came out of them.
  final int totalPumps;

  /// Mean of each day's average feed interval; days with fewer than two
  /// feeds contribute nothing. Null when no day qualifies.
  final int? avgFeedIntervalMinutes;

  /// Averaged across every day in the window, not just active ones — the
  /// honest "typical day" figure for the range.
  final double feedsPerDay;
  final double diapersPerDay;

  bool get isEmpty =>
      totalFeeds == 0 && totalDiapers == 0 && totalPumpedMl == 0;

  /// How many days in the window had anything on them.
  ///
  /// Counted rather than taken from [days].length, which is every day in the
  /// window whether or not anything happened. The export gets this for free
  /// because its list is sparse; this one is dense on purpose, so the charts
  /// show a quiet day as a gap instead of closing it up.
  int get activeDays => days
      .where(
        (d) =>
            d.stats.feedCount > 0 ||
            d.stats.snackCount > 0 ||
            d.stats.diaperCount > 0 ||
            d.stats.pumpCount > 0,
      )
      .length;

  /// Builds the series for `[start, end)`, both normalised to local midnight.
  factory RangeStats.from({
    required DateTime start,
    required DateTime end,
    required List<FeedingEvent> feedings,
    required List<DiaperEvent> diapers,
    List<PumpingEvent> pumps = const [],
  }) {
    DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

    final feedsByDay = <DateTime, List<FeedingEvent>>{};
    for (final f in feedings) {
      feedsByDay.putIfAbsent(dayOf(f.startTime), () => []).add(f);
    }
    final diapersByDay = <DateTime, List<DiaperEvent>>{};
    for (final d in diapers) {
      diapersByDay.putIfAbsent(dayOf(d.time), () => []).add(d);
    }
    final pumpsByDay = <DateTime, List<PumpingEvent>>{};
    for (final p in pumps) {
      pumpsByDay.putIfAbsent(dayOf(p.time), () => []).add(p);
    }

    final days = <TrendPoint>[];
    for (
      var day = dayOf(start);
      day.isBefore(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      days.add((
        day: day,
        stats: DayStats.from(
          feedsByDay[day] ?? const [],
          diapersByDay[day] ?? const [],
          pumps: pumpsByDay[day] ?? const [],
        ),
      ));
    }

    var bottleMl = 0.0;
    var breastMinutes = 0;
    var pumpedMl = 0.0;
    var feedCount = 0;
    var diaperCount = 0;
    var snackCount = 0;
    var pumpCount = 0;
    final intervals = <int>[];
    for (final row in days) {
      bottleMl += row.stats.bottleMl;
      breastMinutes += row.stats.breastMinutes;
      pumpedMl += row.stats.pumpedMl;
      feedCount += row.stats.feedCount;
      diaperCount += row.stats.diaperCount;
      snackCount += row.stats.snackCount;
      pumpCount += row.stats.pumpCount;
      final interval = row.stats.avgFeedIntervalMinutes;
      if (interval != null) intervals.add(interval);
    }

    final avgInterval = intervals.isEmpty
        ? null
        : (intervals.reduce((a, b) => a + b) / intervals.length).round();

    return RangeStats(
      days: days,
      totalFeeds: feedCount,
      totalDiapers: diaperCount,
      totalBottleMl: bottleMl,
      totalBreastMinutes: breastMinutes,
      totalPumpedMl: pumpedMl,
      totalSnacks: snackCount,
      totalPumps: pumpCount,
      avgFeedIntervalMinutes: avgInterval,
      feedsPerDay: days.isEmpty ? 0 : feedCount / days.length,
      diapersPerDay: days.isEmpty ? 0 : diaperCount / days.length,
    );
  }
}
