import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/features/insights/feed_clock_data.dart';
import 'package:flutter_test/flutter_test.dart';

FeedingEvent feed(DateTime at, {String id = 'f'}) =>
    FeedingEvent(id: id, type: FeedingType.bottle, startTime: at);

void main() {
  group('dayFraction', () {
    test('maps the clock onto 0..1', () {
      expect(dayFraction(DateTime(2026, 7, 28, 0, 0)), 0);
      expect(dayFraction(DateTime(2026, 7, 28, 12, 0)), 0.5);
      expect(dayFraction(DateTime(2026, 7, 28, 18, 0)), 0.75);
    });

    test('never reaches 1, so a late feed stays inside its own row', () {
      expect(dayFraction(DateTime(2026, 7, 28, 23, 59)), lessThan(1));
    });

    test('ignores the date, only the time of day', () {
      expect(
        dayFraction(DateTime(2026, 1, 1, 9, 30)),
        dayFraction(DateTime(2026, 12, 31, 9, 30)),
      );
    });
  });

  group('feedClockRows', () {
    final start = DateTime(2026, 7, 20);
    final end = DateTime(2026, 7, 27); // exclusive -> 7 rows

    test('gives one row per day, newest first', () {
      final rows = feedClockRows(start: start, end: end, feedings: const []);
      expect(rows, hasLength(7));
      expect(rows.first.day, DateTime(2026, 7, 26));
      expect(rows.last.day, DateTime(2026, 7, 20));
    });

    test('keeps days with no feeds', () {
      // A gap in the rhythm is the thing this chart exists to show, so an
      // empty day must still take up a row.
      final rows = feedClockRows(
        start: start,
        end: end,
        feedings: [feed(DateTime(2026, 7, 22, 9))],
      );
      expect(rows, hasLength(7));
      expect(rows.where((r) => r.dots.isEmpty), hasLength(6));
    });

    test('files each feed under its own day', () {
      final rows = feedClockRows(
        start: start,
        end: end,
        feedings: [
          feed(DateTime(2026, 7, 26, 8), id: 'newest'),
          feed(DateTime(2026, 7, 20, 8), id: 'oldest'),
        ],
      );
      expect(rows.first.dots.single.event.id, 'newest');
      expect(rows.last.dots.single.event.id, 'oldest');
    });

    test('dayIndex matches the row, so dots paint on their own line', () {
      final rows = feedClockRows(
        start: start,
        end: end,
        feedings: [
          feed(DateTime(2026, 7, 26, 8), id: 'a'),
          feed(DateTime(2026, 7, 24, 8), id: 'b'),
        ],
      );
      for (var i = 0; i < rows.length; i++) {
        for (final dot in rows[i].dots) {
          expect(dot.dayIndex, i);
        }
      }
    });

    test('orders a day\'s feeds by time', () {
      final rows = feedClockRows(
        start: start,
        end: end,
        feedings: [
          feed(DateTime(2026, 7, 22, 18), id: 'evening'),
          feed(DateTime(2026, 7, 22, 6), id: 'morning'),
          feed(DateTime(2026, 7, 22, 12), id: 'midday'),
        ],
      );
      final day = rows.firstWhere((r) => r.day == DateTime(2026, 7, 22));
      expect(day.dots.map((d) => d.event.id).toList(), [
        'morning',
        'midday',
        'evening',
      ]);
    });
  });

  group('longestGapMinutes', () {
    final start = DateTime(2026, 7, 20);
    final end = DateTime(2026, 7, 23);

    test('measures across midnight, not within each day', () {
      // The overnight stretch is the gap people care about, and splitting it
      // at midnight would report two short gaps instead of one long one.
      final rows = feedClockRows(
        start: start,
        end: end,
        feedings: [
          feed(DateTime(2026, 7, 21, 22, 0), id: 'night'),
          feed(DateTime(2026, 7, 22, 5, 0), id: 'morning'),
        ],
      );
      expect(longestGapMinutes(rows), 7 * 60);
    });

    test('picks the longest, not the last', () {
      final rows = feedClockRows(
        start: start,
        end: end,
        feedings: [
          feed(DateTime(2026, 7, 21, 8), id: 'a'),
          feed(DateTime(2026, 7, 21, 14), id: 'b'), // 6h
          feed(DateTime(2026, 7, 21, 16), id: 'c'), // 2h
        ],
      );
      expect(longestGapMinutes(rows), 6 * 60);
    });

    test('needs two feeds to measure between', () {
      final none = feedClockRows(start: start, end: end, feedings: const []);
      expect(longestGapMinutes(none), isNull);

      final one = feedClockRows(
        start: start,
        end: end,
        feedings: [feed(DateTime(2026, 7, 21, 8))],
      );
      expect(longestGapMinutes(one), isNull);
    });
  });
}
