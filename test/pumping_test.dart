import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/activity_entry.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/pumping/pumping_format.dart';
import 'package:baby_app/features/timeline/day_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PumpingFormat.details', () {
    test('joins duration, side, and amount', () {
      final e = PumpingEvent(
        id: 'p',
        time: DateTime(2026, 7, 23, 8),
        durationMinutes: 18,
        side: BreastSide.both,
        amountMl: 120,
      );
      expect(PumpingFormat.details(e), '18 min · Both · 120 ml');
    });

    test('omits missing fields', () {
      final e = PumpingEvent(
        id: 'p',
        time: DateTime(2026, 7, 23, 8),
        amountMl: 90,
      );
      expect(PumpingFormat.details(e), '90 ml');
    });
  });

  test('DayStats sums pumped volume without touching feeding totals', () {
    final stats = DayStats.from(
      const [],
      const [],
      pumps: [
        PumpingEvent(id: 'a', time: DateTime(2026, 7, 23, 6), amountMl: 100),
        PumpingEvent(id: 'b', time: DateTime(2026, 7, 23, 12), amountMl: 80),
      ],
    );
    expect(stats.pumpCount, 2);
    expect(stats.pumpedMl, 180);
    expect(stats.feedCount, 0);
    expect(stats.bottleMl, 0);
  });

  test('mergeActivities interleaves pumps by time', () {
    final entries = mergeActivities(
      [
        FeedingEvent(
          id: 'f',
          type: FeedingType.bottle,
          startTime: DateTime(2026, 7, 23, 9),
        ),
      ],
      [
        DiaperEvent(
          id: 'd',
          type: DiaperType.wet,
          time: DateTime(2026, 7, 23, 7),
        ),
      ],
      pumps: [PumpingEvent(id: 'p', time: DateTime(2026, 7, 23, 8))],
      descending: false,
    );
    expect(entries.map((e) => e.runtimeType).toList(), [
      DiaperEntry, // 07:00
      PumpingEntry, // 08:00
      FeedingEntry, // 09:00
    ]);
  });
}
