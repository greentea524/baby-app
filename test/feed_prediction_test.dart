import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';
import 'package:flutter_test/flutter_test.dart';

FeedingEvent _feed(DateTime at) => FeedingEvent(
  id: at.toIso8601String(),
  type: FeedingType.bottle,
  startTime: at,
);

void main() {
  final base = DateTime(2026, 7, 23, 6);

  group('predictNextFeed', () {
    test('needs at least two feeds', () {
      expect(predictNextFeed(const []).hasPrediction, isFalse);
      expect(predictNextFeed([_feed(base)]).hasPrediction, isFalse);
    });

    test('averages the gaps and projects from the last feed', () {
      // 06:00, 09:00, 12:00 -> gaps of 180 and 180.
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 3))),
        _feed(base.add(const Duration(hours: 6))),
      ];
      final p = predictNextFeed(feeds);
      expect(p.averageIntervalMinutes, 180);
      expect(p.intervalSamples, 2);
      expect(p.nextDue, base.add(const Duration(hours: 9)));
    });

    test('handles unsorted input', () {
      final feeds = [
        _feed(base.add(const Duration(hours: 6))),
        _feed(base),
        _feed(base.add(const Duration(hours: 3))),
      ];
      final p = predictNextFeed(feeds);
      expect(p.averageIntervalMinutes, 180);
      expect(p.lastFeedAt, base.add(const Duration(hours: 6)));
    });

    test('rolling window ignores older gaps', () {
      // One long early gap (10h) then three 2h gaps; window of 3 should
      // average only the recent 2h gaps.
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 10))),
        _feed(base.add(const Duration(hours: 12))),
        _feed(base.add(const Duration(hours: 14))),
        _feed(base.add(const Duration(hours: 16))),
      ];
      final p = predictNextFeed(feeds, window: 3);
      expect(p.averageIntervalMinutes, 120);
      expect(p.intervalSamples, 3);
    });
  });

  group('fixedIntervalDue', () {
    test('adds the interval to the most recent feed', () {
      final feeds = [_feed(base), _feed(base.add(const Duration(hours: 2)))];
      expect(fixedIntervalDue(feeds, 180), base.add(const Duration(hours: 5)));
    });

    test('returns null with no feeds', () {
      expect(fixedIntervalDue(const [], 180), isNull);
    });
  });

  group('countdownLabel', () {
    test('future, now, and overdue', () {
      final due = base;
      expect(
        countdownLabel(due, now: base.subtract(const Duration(minutes: 80))),
        'in 1h 20m',
      );
      expect(
        countdownLabel(due, now: base.subtract(const Duration(minutes: 25))),
        'in 25m',
      );
      expect(countdownLabel(due, now: base), 'due now');
      expect(
        countdownLabel(due, now: base.add(const Duration(minutes: 25))),
        '25m overdue',
      );
      expect(
        countdownLabel(due, now: base.add(const Duration(minutes: 120))),
        '2h overdue',
      );
    });
  });
}
