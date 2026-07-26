import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/features/feeding/feeding_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeedingFormat.timeAgo', () {
    final now = DateTime(2026, 7, 23, 12, 0, 0);

    test('under a minute reads "just now"', () {
      expect(
        FeedingFormat.timeAgo(
          now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        'just now',
      );
    });

    test('minutes', () {
      expect(
        FeedingFormat.timeAgo(
          now.subtract(const Duration(minutes: 23)),
          now: now,
        ),
        '23 min ago',
      );
    });

    test('hours', () {
      expect(
        FeedingFormat.timeAgo(now.subtract(const Duration(hours: 3)), now: now),
        '3 hr ago',
      );
    });

    test('days are singular/plural', () {
      expect(
        FeedingFormat.timeAgo(now.subtract(const Duration(days: 1)), now: now),
        '1 day ago',
      );
      expect(
        FeedingFormat.timeAgo(now.subtract(const Duration(days: 2)), now: now),
        '2 days ago',
      );
    });
  });

  group('FeedingFormat.details', () {
    test('breast shows duration and side', () {
      final e = FeedingEvent(
        id: 'a',
        type: FeedingType.breast,
        startTime: DateTime(2026, 7, 23),
        durationMinutes: 18,
        side: BreastSide.left,
      );
      expect(FeedingFormat.details(e), '18 min · Left');
    });

    test('bottle shows a whole-number amount without decimals', () {
      final e = FeedingEvent(
        id: 'b',
        type: FeedingType.bottle,
        startTime: DateTime(2026, 7, 23),
        amountMl: 120,
      );
      expect(FeedingFormat.details(e), '120 ml (4.1 fl oz)');
    });
  });

  group('FeedingFormat.stopwatch', () {
    test('formats mm:ss and h:mm:ss', () {
      expect(
        FeedingFormat.stopwatch(const Duration(minutes: 5, seconds: 3)),
        '05:03',
      );
      expect(
        FeedingFormat.stopwatch(
          const Duration(hours: 1, minutes: 2, seconds: 4),
        ),
        '1:02:04',
      );
    });
  });
}
