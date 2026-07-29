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

  group('same-session entries (KAN-184)', () {
    /// A steady rhythm of [gapMinutes], oldest first.
    List<FeedingEvent> steady(int count, int gapMinutes) {
      var t = DateTime(2026, 7, 28, 8, 0);
      return [
        for (var i = 0; i < count; i++)
          () {
            final e = FeedingEvent(
              id: 'f$i',
              type: FeedingType.bottle,
              startTime: t,
            );
            t = t.add(Duration(minutes: gapMinutes));
            return e;
          }(),
      ];
    }

    test('a topped-up bottle does not drag the average down', () {
      final feeds = steady(8, 78);
      final baseline = predictNextFeed(feeds);
      expect(baseline.averageIntervalMinutes, 78);

      // A second bottle a minute after the last: one feed logged twice.
      final withSplit = [
        ...feeds,
        FeedingEvent(
          id: 'topup',
          type: FeedingType.bottle,
          startTime: feeds.last.startTime.add(const Duration(minutes: 1)),
        ),
      ];
      // Before the fix this averaged to 68, pulling every later reminder ten
      // minutes early.
      expect(predictNextFeed(withSplit).averageIntervalMinutes, 78);
    });

    test('several splits still leave the rhythm intact', () {
      final feeds = [...steady(8, 78)];
      for (var i = 0; i < 3; i++) {
        feeds.add(
          FeedingEvent(
            id: 'split$i',
            type: FeedingType.bottle,
            startTime: feeds.last.startTime.add(const Duration(minutes: 2)),
          ),
        );
      }
      expect(predictNextFeed(feeds).averageIntervalMinutes, 78);
    });

    test('discarded gaps do not consume window slots', () {
      // Filtering happens before windowing, so the average still draws on
      // eight real intervals rather than however many survived.
      final feeds = [...steady(9, 78)];
      feeds.insert(
        4,
        FeedingEvent(
          id: 'split',
          type: FeedingType.bottle,
          startTime: feeds[3].startTime.add(const Duration(minutes: 1)),
        ),
      );
      final p = predictNextFeed(feeds);
      expect(p.averageIntervalMinutes, 78);
      expect(p.intervalSamples, 8);
    });

    test('genuine cluster feeding is still predicted from', () {
      // Every gap under the threshold is a real pattern, not logging noise —
      // refusing to predict would be worse than predicting short.
      final feeds = steady(5, 12);
      final p = predictNextFeed(feeds);
      expect(p.averageIntervalMinutes, 12);
      expect(p.nextDue, isNotNull);
    });

    test('the threshold is adjustable', () {
      final feeds = steady(4, 30);
      expect(
        predictNextFeed(feeds, minGapMinutes: 45).averageIntervalMinutes,
        30,
      );
    });

    test('the prediction still counts from the most recent feed', () {
      final feeds = steady(8, 78);
      final topUp = feeds.last.startTime.add(const Duration(minutes: 1));
      final withSplit = [
        ...feeds,
        FeedingEvent(id: 't', type: FeedingType.bottle, startTime: topUp),
      ];
      // The baby ate at the top-up time, so that is what the gap runs from.
      expect(
        predictNextFeed(withSplit).nextDue,
        topUp.add(const Duration(minutes: 78)),
      );
    });
  });
}
