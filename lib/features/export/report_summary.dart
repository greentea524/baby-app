import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';
import '../timeline/day_stats.dart';
import 'export_data.dart';

/// One day's aggregate in the report.
typedef DailyRow = ({DateTime day, DayStats stats});

/// Aggregates an [ExportData] window into the figures the PDF report shows
/// (KAN-165). Pure, so the arithmetic is unit-testable.
class ReportSummary {
  const ReportSummary({
    required this.daily,
    required this.totalFeeds,
    required this.totalSnacks,
    required this.totalDiapers,
    required this.totalBottleMl,
    required this.totalBreastMinutes,
    required this.avgFeedIntervalMinutes,
    required this.feedsPerDay,
  });

  final List<DailyRow> daily;
  /// Full feeds. Top-ups are counted in [totalSnacks] instead, so a figure
  /// handed to a pediatrician does not read a 10 ml snack as a feed.
  final int totalFeeds;

  /// Top-ups marked as snacks. Their volume still counts toward
  /// [totalBottleMl] and [totalBreastMinutes] — the baby drank it.
  final int totalSnacks;
  final int totalDiapers;
  final double totalBottleMl;
  final int totalBreastMinutes;

  /// Mean of each day's average feed interval (days with <2 feeds excluded).
  final int? avgFeedIntervalMinutes;

  /// Average feeds per day across days that have any activity.
  final double feedsPerDay;

  factory ReportSummary.from(ExportData data) {
    DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

    final feedsByDay = <DateTime, List<FeedingEvent>>{};
    for (final f in data.feedings) {
      feedsByDay.putIfAbsent(dayOf(f.startTime), () => []).add(f);
    }
    final diapersByDay = <DateTime, List<DiaperEvent>>{};
    for (final d in data.diapers) {
      diapersByDay.putIfAbsent(dayOf(d.time), () => []).add(d);
    }

    final days = {...feedsByDay.keys, ...diapersByDay.keys}.toList()..sort();
    final daily = [
      for (final day in days)
        (
          day: day,
          stats: DayStats.from(
            feedsByDay[day] ?? const [],
            diapersByDay[day] ?? const [],
          ),
        ),
    ];

    var bottleMl = 0.0;
    var breastMinutes = 0;
    final intervals = <int>[];
    for (final row in daily) {
      bottleMl += row.stats.bottleMl;
      breastMinutes += row.stats.breastMinutes;
      final interval = row.stats.avgFeedIntervalMinutes;
      if (interval != null) intervals.add(interval);
    }

    final avgInterval = intervals.isEmpty
        ? null
        : (intervals.reduce((a, b) => a + b) / intervals.length).round();

    final fullFeeds = data.feedings.where((f) => !f.isSnack).length;

    return ReportSummary(
      daily: daily,
      totalFeeds: fullFeeds,
      totalSnacks: data.feedings.length - fullFeeds,
      totalDiapers: data.diapers.length,
      totalBottleMl: bottleMl,
      totalBreastMinutes: breastMinutes,
      avgFeedIntervalMinutes: avgInterval,
      feedsPerDay: daily.isEmpty ? 0 : fullFeeds / daily.length,
    );
  }
}
