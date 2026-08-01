import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/features/timeline/day_stats.dart';
import 'package:flutter_test/flutter_test.dart';

FeedingEvent _breast(DateTime t, int min) => FeedingEvent(
  id: t.toIso8601String(),
  type: FeedingType.breast,
  startTime: t,
  durationMinutes: min,
);

FeedingEvent _bottle(DateTime t, double ml) => FeedingEvent(
  id: t.toIso8601String(),
  type: FeedingType.bottle,
  startTime: t,
  amountMl: ml,
);

DiaperEvent _diaper(DiaperType type) =>
    DiaperEvent(id: '$type', type: type, time: DateTime(2026, 7, 23));

void main() {
  final day = DateTime(2026, 7, 23);

  test('averages the interval between consecutive feeds', () {
    final stats = DayStats.from([
      _breast(day.add(const Duration(hours: 8)), 15),
      _breast(day.add(const Duration(hours: 9, minutes: 30)), 20),
      _breast(day.add(const Duration(hours: 11)), 10),
    ], const []);

    expect(stats.feedCount, 3);
    expect(stats.avgFeedIntervalMinutes, 90); // 90 and 90
    expect(stats.breastMinutes, 45);
  });

  test('avg interval is null with fewer than two feeds', () {
    final stats = DayStats.from([_breast(day, 12)], const []);
    expect(stats.avgFeedIntervalMinutes, isNull);
  });

  test('sorts unordered feeds before computing intervals', () {
    final stats = DayStats.from([
      _bottle(day.add(const Duration(hours: 12)), 100),
      _bottle(day.add(const Duration(hours: 10)), 120),
    ], const []);
    expect(stats.avgFeedIntervalMinutes, 120);
    expect(stats.bottleMl, 220);
  });

  test('counts diapers by type', () {
    final stats = DayStats.from(const [], [
      _diaper(DiaperType.wet),
      _diaper(DiaperType.wet),
      _diaper(DiaperType.dirty),
      _diaper(DiaperType.both),
    ]);
    expect(stats.diaperCount, 4);
    expect(stats.wetCount, 2);
    expect(stats.dirtyCount, 1);
    expect(stats.bothCount, 1);
  });

  group('snacks', () {
    FeedingEvent feed(int hour, {bool isSnack = false}) => FeedingEvent(
      id: 'f$hour',
      type: FeedingType.bottle,
      startTime: DateTime(2026, 7, 30, hour),
      amountMl: isSnack ? 10 : 120,
      isSnack: isSnack,
    );

    test('are counted apart from feeds', () {
      final stats = DayStats.from([
        feed(7),
        feed(8, isSnack: true),
        feed(10),
      ], const []);
      expect(stats.feedCount, 2);
      expect(stats.snackCount, 1);
    });

    test('do not drag the average interval down', () {
      // 7:00 and 10:00 is a 3-hour rhythm. Counting the 8:00 top-up as a
      // boundary would report 90 minutes instead — the error the reminders
      // used to make.
      final stats = DayStats.from([
        feed(7),
        feed(8, isSnack: true),
        feed(10),
      ], const []);
      expect(stats.avgFeedIntervalMinutes, 180);
    });

    test('still count toward the volume drunk', () {
      // The baby did drink it; total intake includes it even though it is
      // not a feed in its own right.
      final stats = DayStats.from([feed(7), feed(8, isSnack: true)], const []);
      expect(stats.bottleMl, 130);
    });

    test('a day without snacks reports none', () {
      final stats = DayStats.from([feed(7), feed(10)], const []);
      expect(stats.snackCount, 0);
      expect(stats.feedCount, 2);
    });
  });
}
