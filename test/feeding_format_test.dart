import 'package:baby_app/core/format/unit_system.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/features/feeding/feeding_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Evaluates a context-dependent formatter inside a real MaterialApp, which
/// TimeOfDay.format needs for its localizations.
Future<String> _stamp(
  WidgetTester tester,
  DateTime time, {
  required DateTime now,
}) async {
  late String result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          result = FeedingFormat.clockStamp(context, time, now: now);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

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

    test('whole hours omit minutes', () {
      expect(
        FeedingFormat.timeAgo(now.subtract(const Duration(hours: 3)), now: now),
        '3 hr ago',
      );
    });

    test('hours carry the trailing minutes', () {
      expect(
        FeedingFormat.timeAgo(
          now.subtract(const Duration(hours: 2, minutes: 35)),
          now: now,
        ),
        '2 hr 35 min ago',
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
      expect(FeedingFormat.details(e, UnitSystem.us), '18 min · Left');
    });

    test('bottle shows a whole-number amount without decimals', () {
      final e = FeedingEvent(
        id: 'b',
        type: FeedingType.bottle,
        startTime: DateTime(2026, 7, 23),
        amountMl: 120,
      );
      expect(FeedingFormat.details(e, UnitSystem.us), '120 ml (4.1 fl oz)');
      // Metric drops the conversion rather than showing both.
      expect(FeedingFormat.details(e, UnitSystem.metric), '120 ml');
    });
  });

  group('FeedingFormat.eventLabel', () {
    FeedingEvent feed({required bool isSnack, FeedingType? type}) =>
        FeedingEvent(
          id: 'f1',
          type: type ?? FeedingType.bottle,
          startTime: DateTime(2026, 7, 30, 9),
          isSnack: isSnack,
        );

    test('a full feed reads as its type', () {
      expect(FeedingFormat.eventLabel(feed(isSnack: false)), 'Bottle');
      expect(
        FeedingFormat.eventLabel(feed(isSnack: false, type: FeedingType.breast)),
        'Breastfeeding',
      );
    });

    test('a snack says so', () {
      // Otherwise it is indistinguishable from a full feed in the activity
      // list, while the next-feed clock quietly ignores it.
      expect(FeedingFormat.eventLabel(feed(isSnack: true)), 'Bottle · Snack');
      expect(
        FeedingFormat.eventLabel(feed(isSnack: true, type: FeedingType.breast)),
        'Breastfeeding · Snack',
      );
    });

    test('keeps the type, rather than replacing it', () {
      // "Snack" alone would lose whether it was a bottle or the breast.
      final label = FeedingFormat.eventLabel(feed(isSnack: true));
      expect(label, contains('Bottle'));
      expect(label, contains('Snack'));
    });
  });

  group('FeedingFormat.clockStamp', () {
    final now = DateTime(2026, 7, 23, 15, 0);

    testWidgets('shows just the clock time for an entry from today', (
      tester,
    ) async {
      final stamp = await _stamp(
        tester,
        DateTime(2026, 7, 23, 9, 30),
        now: now,
      );
      expect(stamp, '9:30 AM');
    });

    testWidgets('prefixes a short date once the entry is from another day', (
      tester,
    ) async {
      // Without the date, a row logged days ago would read as if it were
      // this morning.
      final stamp = await _stamp(
        tester,
        DateTime(2026, 7, 21, 9, 30),
        now: now,
      );
      expect(stamp, 'Jul 21, 9:30 AM');
    });

    testWidgets('treats just-past-midnight as a different day', (tester) async {
      final stamp = await _stamp(
        tester,
        DateTime(2026, 7, 22, 23, 45),
        now: now,
      );
      expect(stamp, 'Jul 22, 11:45 PM');
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
