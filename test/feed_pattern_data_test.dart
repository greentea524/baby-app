import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/features/insights/feed_pattern_data.dart';

void main() {
  FeedingEvent feed(
    DateTime at, {
    FeedingType type = FeedingType.bottle,
    bool snack = false,
  }) => FeedingEvent(
    id: at.toIso8601String(),
    type: type,
    startTime: at,
    isSnack: snack,
  );

  final days = [
    DateTime(2026, 7, 27),
    DateTime(2026, 7, 28),
    DateTime(2026, 7, 29),
  ];

  group('countsAsMilk', () {
    test('keeps snacks, because a 2am top-up is still a waking', () {
      expect(countsAsMilk(feed(DateTime(2026, 7, 28, 2), snack: true)), isTrue);
    });

    test('drops solids, which run on their own schedule', () {
      expect(
        countsAsMilk(feed(DateTime(2026, 7, 28, 12), type: FeedingType.solids)),
        isFalse,
      );
    });
  });

  group('nightStretchMinutes', () {
    test('measures the gap across midnight for the night it belongs to', () {
      final stretches = nightStretchMinutes(
        days: days,
        feedings: [
          feed(DateTime(2026, 7, 28, 22)),
          feed(DateTime(2026, 7, 29, 4)),
        ],
      );
      // The night that begins on the 28th, not the morning it ended on.
      expect(stretches, [0, 6 * 60, 0]);
    });

    test('keeps the longest of several gaps in one night', () {
      final stretches = nightStretchMinutes(
        days: days,
        feedings: [
          feed(DateTime(2026, 7, 28, 20)),
          feed(DateTime(2026, 7, 28, 23)),
          feed(DateTime(2026, 7, 29, 5)),
          feed(DateTime(2026, 7, 29, 6, 30)),
        ],
      );
      expect(stretches[1], 6 * 60);
    });

    test('ignores daytime gaps, however long', () {
      final stretches = nightStretchMinutes(
        days: days,
        feedings: [
          feed(DateTime(2026, 7, 28, 9)),
          feed(DateTime(2026, 7, 28, 16)),
        ],
      );
      // Seven hours, but its midpoint is half past twelve — an afternoon,
      // not a night.
      expect(stretches, [0, 0, 0]);
    });

    test('counts an early night that starts before the window opens', () {
      // The midpoint rule exists for this case: the gap begins at 18:30,
      // before 7pm, and ends at 08:00, after 7am.
      final stretches = nightStretchMinutes(
        days: days,
        feedings: [
          feed(DateTime(2026, 7, 28, 18, 30)),
          feed(DateTime(2026, 7, 29, 8)),
        ],
      );
      expect(stretches[1], 13 * 60 + 30);
    });

    test('a snack in the small hours breaks the stretch', () {
      final stretches = nightStretchMinutes(
        days: days,
        feedings: [
          feed(DateTime(2026, 7, 28, 22)),
          feed(DateTime(2026, 7, 29, 1)),
          feed(DateTime(2026, 7, 29, 4)),
        ],
      );
      expect(
        stretches[1],
        3 * 60,
        reason: 'she woke at 1am, so the night was not six hours',
      );

      final ignoringSnacks = nightStretchMinutes(
        days: days,
        feedings: [
          feed(DateTime(2026, 7, 28, 22)),
          feed(DateTime(2026, 7, 29, 1), snack: true),
          feed(DateTime(2026, 7, 29, 4)),
        ],
      );
      expect(ignoringSnacks[1], 3 * 60);
    });

    test('solids never count as the end of a night', () {
      final stretches = nightStretchMinutes(
        days: days,
        feedings: [
          feed(DateTime(2026, 7, 28, 21)),
          feed(DateTime(2026, 7, 29, 2), type: FeedingType.solids),
          feed(DateTime(2026, 7, 29, 6)),
        ],
      );
      expect(stretches[1], 9 * 60);
    });

    test('a night still waiting on its next feed reads zero', () {
      // Nothing has closed the gap yet, and an open-ended stretch is not a
      // measurement.
      final stretches = nightStretchMinutes(
        days: days,
        feedings: [feed(DateTime(2026, 7, 29, 21))],
      );
      expect(stretches, [0, 0, 0]);
    });

    test('returns one entry per day, zeros included', () {
      final stretches = nightStretchMinutes(days: days, feedings: const []);
      expect(stretches, [0, 0, 0]);
    });

    test('drops gaps whose night is outside the range', () {
      final stretches = nightStretchMinutes(
        days: days,
        feedings: [
          feed(DateTime(2026, 7, 20, 22)),
          feed(DateTime(2026, 7, 21, 5)),
        ],
      );
      expect(stretches, [0, 0, 0]);
    });
  });

  group('feedsByHour', () {
    test('always returns 24 buckets, midnight first', () {
      final counts = feedsByHour(const []);
      expect(counts, hasLength(24));
      expect(counts.every((c) => c == 0), isTrue);
    });

    test('buckets by the hour the feed started', () {
      final counts = feedsByHour([
        feed(DateTime(2026, 7, 28, 3, 5)),
        feed(DateTime(2026, 7, 28, 3, 55)),
        feed(DateTime(2026, 7, 29, 3, 30)),
        feed(DateTime(2026, 7, 29, 14)),
      ]);
      expect(counts[3], 3, reason: 'stacked across days');
      expect(counts[14], 1);
      expect(counts[4], 0);
    });

    test('counts snacks and skips solids', () {
      final counts = feedsByHour([
        feed(DateTime(2026, 7, 28, 2), snack: true),
        feed(DateTime(2026, 7, 28, 12), type: FeedingType.solids),
      ]);
      expect(counts[2], 1);
      expect(counts[12], 0);
    });
  });

  group('hourLabel', () {
    test('reads as a 12-hour clock', () {
      expect(hourLabel(0), '12a');
      expect(hourLabel(7), '7a');
      expect(hourLabel(11), '11a');
      expect(hourLabel(12), '12p');
      expect(hourLabel(19), '7p');
      expect(hourLabel(23), '11p');
    });
  });
}
