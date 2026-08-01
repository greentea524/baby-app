import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/pumping_event.dart';

/// Summary statistics for one day's events (KAN-153). Pure/derivable so it
/// can be unit-tested and reused by export/reporting later.
class DayStats {
  const DayStats({
    required this.feedCount,
    required this.snackCount,
    required this.avgFeedIntervalMinutes,
    required this.breastMinutes,
    required this.bottleMl,
    required this.diaperCount,
    required this.wetCount,
    required this.dirtyCount,
    required this.bothCount,
    this.pumpCount = 0,
    this.pumpedMl = 0,
  });

  /// Full feeds — top-ups are counted separately in [snackCount], so a day
  /// with four feeds and three small top-ups does not read as seven feeds.
  final int feedCount;

  /// Top-ups the caregiver marked as snacks. Their volume still counts toward
  /// [bottleMl] and [breastMinutes]: the baby did drink it, so total intake
  /// includes it — it just is not a feed in its own right.
  final int snackCount;

  /// Mean minutes between consecutive feeds; null when fewer than 2 feeds.
  final int? avgFeedIntervalMinutes;

  final int breastMinutes;
  final double bottleMl;

  final int diaperCount;
  final int wetCount;
  final int dirtyCount;
  final int bothCount;

  final int pumpCount;
  final double pumpedMl;

  factory DayStats.from(
    List<FeedingEvent> feedings,
    List<DiaperEvent> diapers, {
    List<PumpingEvent> pumps = const [],
  }) {
    final feeds = [...feedings]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // Only feeds that end one feeding cycle and start the next mark an
    // interval. Counting a top-up as a boundary halves the reported average —
    // the same error the reminders used to make.
    final rhythm = feeds.where((f) => f.drivesFeedClock).toList();

    int? avgInterval;
    if (rhythm.length >= 2) {
      var totalMinutes = 0;
      for (var i = 1; i < rhythm.length; i++) {
        totalMinutes += rhythm[i].startTime
            .difference(rhythm[i - 1].startTime)
            .inMinutes;
      }
      avgInterval = (totalMinutes / (rhythm.length - 1)).round();
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

    var pumpedMl = 0.0;
    for (final p in pumps) {
      pumpedMl += p.amountMl ?? 0;
    }

    return DayStats(
      feedCount: feeds.where((f) => !f.isSnack).length,
      snackCount: feeds.where((f) => f.isSnack).length,
      avgFeedIntervalMinutes: avgInterval,
      breastMinutes: breastMinutes,
      bottleMl: bottleMl,
      diaperCount: diapers.length,
      wetCount: wet,
      dirtyCount: dirty,
      bothCount: both,
      pumpCount: pumps.length,
      pumpedMl: pumpedMl,
    );
  }
}
