import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/insights/range_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 7, 20);
  final end = DateTime(2026, 7, 27); // exclusive -> 7 days

  RangeStats build({
    List<FeedingEvent> feedings = const [],
    List<DiaperEvent> diapers = const [],
    List<PumpingEvent> pumps = const [],
  }) => RangeStats.from(
    start: start,
    end: end,
    feedings: feedings,
    diapers: diapers,
    pumps: pumps,
  );

  test('produces one row per day, including days with no activity', () {
    final stats = build(
      feedings: [
        FeedingEvent(
          id: 'f',
          type: FeedingType.bottle,
          startTime: DateTime(2026, 7, 22, 9),
          amountMl: 120,
        ),
      ],
    );
    expect(stats.days.length, 7);
    expect(stats.days.first.day, DateTime(2026, 7, 20));
    expect(stats.days.last.day, DateTime(2026, 7, 26));
    // The quiet days are present as zeros rather than being skipped.
    expect(stats.days[0].stats.feedCount, 0);
    expect(stats.days[2].stats.feedCount, 1);
  });

  test('averages across every day in the window, not just active ones', () {
    final stats = build(
      feedings: [
        for (var i = 0; i < 7; i++)
          FeedingEvent(
            id: 'f$i',
            type: FeedingType.breast,
            startTime: DateTime(2026, 7, 22, 8 + i),
            durationMinutes: 10,
          ),
      ],
    );
    // 7 feeds all on one day, but spread over a 7-day window.
    expect(stats.totalFeeds, 7);
    expect(stats.feedsPerDay, closeTo(1.0, 0.001));
  });

  test('sums bottle, breast, and pumped volumes over the range', () {
    final stats = build(
      feedings: [
        FeedingEvent(
          id: 'b1',
          type: FeedingType.bottle,
          startTime: DateTime(2026, 7, 21, 9),
          amountMl: 120,
        ),
        FeedingEvent(
          id: 'b2',
          type: FeedingType.bottle,
          startTime: DateTime(2026, 7, 23, 9),
          amountMl: 100,
        ),
        FeedingEvent(
          id: 'br',
          type: FeedingType.breast,
          startTime: DateTime(2026, 7, 23, 15),
          durationMinutes: 18,
        ),
      ],
      pumps: [
        PumpingEvent(id: 'p', time: DateTime(2026, 7, 24, 7), amountMl: 90),
      ],
    );
    expect(stats.totalBottleMl, 220);
    expect(stats.totalBreastMinutes, 18);
    expect(stats.totalPumpedMl, 90);
  });

  test('counts diapers and reports a per-day average', () {
    final stats = build(
      diapers: [
        DiaperEvent(
          id: 'd1',
          type: DiaperType.wet,
          time: DateTime(2026, 7, 20, 8),
        ),
        DiaperEvent(
          id: 'd2',
          type: DiaperType.dirty,
          time: DateTime(2026, 7, 20, 12),
        ),
        DiaperEvent(
          id: 'd3',
          type: DiaperType.both,
          time: DateTime(2026, 7, 25, 12),
        ),
      ],
    );
    expect(stats.totalDiapers, 3);
    expect(stats.diapersPerDay, closeTo(3 / 7, 0.001));
  });

  test('averages the per-day feed intervals, skipping single-feed days', () {
    final stats = build(
      feedings: [
        // Day A: 8:00 and 11:00 -> 180 min interval.
        FeedingEvent(
          id: 'a1',
          type: FeedingType.breast,
          startTime: DateTime(2026, 7, 21, 8),
        ),
        FeedingEvent(
          id: 'a2',
          type: FeedingType.breast,
          startTime: DateTime(2026, 7, 21, 11),
        ),
        // Day B: a lone feed contributes no interval.
        FeedingEvent(
          id: 'b1',
          type: FeedingType.breast,
          startTime: DateTime(2026, 7, 23, 9),
        ),
      ],
    );
    expect(stats.avgFeedIntervalMinutes, 180);
  });

  test('an empty window is reported as empty', () {
    final stats = build();
    expect(stats.isEmpty, isTrue);
    expect(stats.days.length, 7);
    expect(stats.avgFeedIntervalMinutes, isNull);
    expect(stats.feedsPerDay, 0);
  });
}
