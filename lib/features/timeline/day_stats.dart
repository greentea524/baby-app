import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';

/// Summary statistics for one day's events (KAN-153). Pure/derivable so it
/// can be unit-tested and reused by export/reporting later.
class DayStats {
  const DayStats({
    required this.feedCount,
    required this.avgFeedIntervalMinutes,
    required this.breastMinutes,
    required this.bottleMl,
    required this.diaperCount,
    required this.wetCount,
    required this.dirtyCount,
    required this.bothCount,
  });

  final int feedCount;

  /// Mean minutes between consecutive feeds; null when fewer than 2 feeds.
  final int? avgFeedIntervalMinutes;

  final int breastMinutes;
  final double bottleMl;

  final int diaperCount;
  final int wetCount;
  final int dirtyCount;
  final int bothCount;

  factory DayStats.from(
    List<FeedingEvent> feedings,
    List<DiaperEvent> diapers,
  ) {
    final feeds = [...feedings]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    int? avgInterval;
    if (feeds.length >= 2) {
      var totalMinutes = 0;
      for (var i = 1; i < feeds.length; i++) {
        totalMinutes += feeds[i].startTime
            .difference(feeds[i - 1].startTime)
            .inMinutes;
      }
      avgInterval = (totalMinutes / (feeds.length - 1)).round();
    }

    var breastMinutes = 0;
    var bottleMl = 0.0;
    for (final f in feeds) {
      if (f.type == FeedingType.breast) {
        breastMinutes += f.durationMinutes ?? 0;
      } else if (f.type == FeedingType.bottle) {
        bottleMl += f.amountMl ?? 0;
      }
    }

    var wet = 0, dirty = 0, both = 0;
    for (final d in diapers) {
      switch (d.type) {
        case DiaperType.wet:
          wet++;
        case DiaperType.dirty:
          dirty++;
        case DiaperType.both:
          both++;
      }
    }

    return DayStats(
      feedCount: feeds.length,
      avgFeedIntervalMinutes: avgInterval,
      breastMinutes: breastMinutes,
      bottleMl: bottleMl,
      diaperCount: diapers.length,
      wetCount: wet,
      dirtyCount: dirty,
      bothCount: both,
    );
  }
}
