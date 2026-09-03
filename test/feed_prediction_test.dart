import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';
import 'package:flutter_test/flutter_test.dart';

FeedingEvent _feed(DateTime at) => FeedingEvent(
  id: at.toIso8601String(),
  type: FeedingType.bottle,
  startTime: at,
);

/// A steady rhythm of [gapMinutes], oldest first.
List<FeedingEvent> _steady(int count, int gapMinutes) {
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

void main() {
  final base = DateTime(2026, 7, 23, 6);

  group('feedRhythm', () {
    test('needs at least two feeds', () {
      expect(feedRhythm(const []).hasRhythm, isFalse);
      expect(feedRhythm([_feed(base)]).hasRhythm, isFalse);
    });

    test('reports the typical gap', () {
      // 06:00, 09:00, 12:00 -> gaps of 180 and 180.
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 3))),
        _feed(base.add(const Duration(hours: 6))),
      ];
      final r = feedRhythm(feeds);
      expect(r.typicalGapMinutes, 180);
      expect(r.samples, 2);
    });

    test('handles unsorted input', () {
      final feeds = [
        _feed(base.add(const Duration(hours: 6))),
        _feed(base),
        _feed(base.add(const Duration(hours: 3))),
      ];
      expect(feedRhythm(feeds).typicalGapMinutes, 180);
    });

    test('rolling window ignores older gaps', () {
      // One long early gap (10h) then three 2h gaps; a window of 3 should see
      // only the recent 2h gaps.
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 10))),
        _feed(base.add(const Duration(hours: 12))),
        _feed(base.add(const Duration(hours: 14))),
        _feed(base.add(const Duration(hours: 16))),
      ];
      final r = feedRhythm(feeds, window: 3);
      expect(r.typicalGapMinutes, 120);
      expect(r.samples, 3);
    });

    test('an even number of gaps averages the middle pair', () {
      // Gaps of 120 and 180 -> median 150.
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 2))),
        _feed(base.add(const Duration(hours: 5))),
      ];
      expect(feedRhythm(feeds).typicalGapMinutes, 150);
    });

    test('a night stretch does not distort the daytime figure', () {
      // The case that retired the predictive reminder: 3-hourly from 07:00
      // with one 6h overnight gap. The mean lands at 206 minutes, describing
      // neither half of the day; the median reports the 180 the day runs at.
      final day = DateTime(2026, 7, 30);
      final feeds = [
        for (final h in [7, 10, 13, 16, 19, 22, 28, 31])
          _feed(day.add(Duration(hours: h))),
      ];
      final gaps = recentFeedGaps(feeds);
      final mean = gaps.reduce((a, b) => a + b) / gaps.length;

      expect(mean.round(), 206, reason: 'the old averaging behaviour');
      expect(feedRhythm(feeds).typicalGapMinutes, 180);
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

  group('feedDueState', () {
    final due = base;
    FeedDueState at(Duration before) =>
        feedDueState(due, now: due.subtract(before));

    test('amber for the last quarter hour', () {
      expect(at(const Duration(minutes: 16)), FeedDueState.upcoming);
      expect(at(const Duration(minutes: 15)), FeedDueState.soon);
      expect(at(const Duration(minutes: 1)), FeedDueState.soon);
    });

    test('due now counts as overdue, not as soon', () {
      // The chip's wording flips to "overdue" here, so the colour has to
      // flip with it or the two contradict each other.
      expect(feedDueState(due, now: due), FeedDueState.overdue);
      expect(
        feedDueState(due, now: due.add(const Duration(minutes: 30))),
        FeedDueState.overdue,
      );
    });

    test('hours out is just upcoming', () {
      expect(at(const Duration(hours: 3)), FeedDueState.upcoming);
    });

    test('the window is adjustable', () {
      expect(
        feedDueState(
          due,
          now: due.subtract(const Duration(minutes: 25)),
          within: const Duration(minutes: 30),
        ),
        FeedDueState.soon,
      );
    });
  });

  group('same-session entries (KAN-184)', () {
    test('a topped-up bottle does not drag the figure down', () {
      final feeds = _steady(8, 78);
      expect(feedRhythm(feeds).typicalGapMinutes, 78);

      // A second bottle a minute after the last: one feed logged twice.
      final withSplit = [
        ...feeds,
        FeedingEvent(
          id: 'topup',
          type: FeedingType.bottle,
          startTime: feeds.last.startTime.add(const Duration(minutes: 1)),
        ),
      ];
      expect(feedRhythm(withSplit).typicalGapMinutes, 78);
    });

    test('several splits still leave the rhythm intact', () {
      final feeds = [..._steady(8, 78)];
      for (var i = 0; i < 3; i++) {
        feeds.add(
          FeedingEvent(
            id: 'split$i',
            type: FeedingType.bottle,
            startTime: feeds.last.startTime.add(const Duration(minutes: 2)),
          ),
        );
      }
      expect(feedRhythm(feeds).typicalGapMinutes, 78);
    });

    test('discarded gaps do not consume window slots', () {
      // Filtering happens before windowing, so the figure still draws on
      // eight real intervals rather than however many survived.
      final feeds = [..._steady(9, 78)];
      feeds.insert(
        4,
        FeedingEvent(
          id: 'split',
          type: FeedingType.bottle,
          startTime: feeds[3].startTime.add(const Duration(minutes: 1)),
        ),
      );
      final r = feedRhythm(feeds);
      expect(r.typicalGapMinutes, 78);
      expect(r.samples, 8);
    });

    test('genuine cluster feeding is still reported', () {
      // Every gap under the threshold is a real pattern, not logging noise —
      // reporting nothing would be worse than reporting a short rhythm.
      final r = feedRhythm(_steady(5, 12));
      expect(r.typicalGapMinutes, 12);
      expect(r.hasRhythm, isTrue);
    });

    test('the threshold is adjustable', () {
      expect(
        feedRhythm(_steady(4, 30), minGapMinutes: 45).typicalGapMinutes,
        30,
      );
    });

    test('the fixed interval counts from the most recent feed', () {
      final feeds = _steady(8, 78);
      final topUp = feeds.last.startTime.add(const Duration(minutes: 1));
      final withSplit = [
        ...feeds,
        FeedingEvent(id: 't', type: FeedingType.bottle, startTime: topUp),
      ];
      // The baby ate at the top-up time, so that is what the gap runs from.
      expect(
        fixedIntervalDue(withSplit, 78),
        topUp.add(const Duration(minutes: 78)),
      );
    });
  });

  group('snacks', () {
    FeedingEvent snack(DateTime at, {String id = 'snack'}) => FeedingEvent(
      id: id,
      type: FeedingType.bottle,
      startTime: at,
      amountMl: 10,
      isSnack: true,
    );

    test('a snack does not enter the rhythm', () {
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 3))),
        _feed(base.add(const Duration(hours: 6))),
        snack(base.add(const Duration(hours: 7))),
        _feed(base.add(const Duration(hours: 9))),
      ];
      final r = feedRhythm(feeds);
      // Gaps are 180/180/180, not 180/180/60/120.
      expect(r.typicalGapMinutes, 180);
      expect(r.samples, 3);
    });

    test('a snack does not reset the fixed-interval clock', () {
      // The dangerous case: a 4h safety floor silently becoming 5h.
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 4))),
        snack(base.add(const Duration(hours: 5))),
      ];
      expect(fixedIntervalDue(feeds, 240), base.add(const Duration(hours: 8)));
    });

    test('snack-only history still yields a reminder', () {
      // Going silent is worse than reminding from imperfect data.
      final feeds = [
        snack(base, id: 's1'),
        snack(base.add(const Duration(hours: 2)), id: 's2'),
      ];
      expect(feedRhythm(feeds).hasRhythm, isTrue);
      expect(fixedIntervalDue(feeds, 180), base.add(const Duration(hours: 5)));
    });

    test('a lone full feed among snacks falls back rather than giving up', () {
      final feeds = [
        snack(base, id: 's1'),
        _feed(base.add(const Duration(hours: 2))),
        snack(base.add(const Duration(hours: 3)), id: 's2'),
      ];
      expect(feedRhythm(feeds).hasRhythm, isTrue);
      // One non-snack is still a usable anchor for a fixed interval.
      expect(fixedIntervalDue(feeds, 180), base.add(const Duration(hours: 5)));
    });

    test('feeds default to full so existing history is unaffected', () {
      expect(_feed(base).isSnack, isFalse);
    });
  });

  group('solids', () {
    FeedingEvent solids(DateTime at, {String id = 'solids'}) =>
        FeedingEvent(id: id, type: FeedingType.solids, startTime: at);

    test('solids do not enter the rhythm', () {
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 3))),
        solids(base.add(const Duration(hours: 4))),
        _feed(base.add(const Duration(hours: 6))),
      ];
      final r = feedRhythm(feeds);
      expect(r.typicalGapMinutes, 180);
      expect(r.samples, 2);
    });

    test('solids do not reset the fixed-interval clock', () {
      final feeds = [
        _feed(base),
        _feed(base.add(const Duration(hours: 4))),
        solids(base.add(const Duration(hours: 5))),
      ];
      expect(fixedIntervalDue(feeds, 240), base.add(const Duration(hours: 8)));
    });

    test('a weaned baby on solids alone still gets a reminder', () {
      final feeds = [
        solids(base, id: 's1'),
        solids(base.add(const Duration(hours: 4)), id: 's2'),
      ];
      expect(feedRhythm(feeds).hasRhythm, isTrue);
      expect(fixedIntervalDue(feeds, 240), isNotNull);
    });

    test('drivesFeedClock covers both exclusions', () {
      expect(drivesFeedClock(_feed(base)), isTrue);
      expect(drivesFeedClock(solids(base)), isFalse);
      expect(
        drivesFeedClock(
          FeedingEvent(
            id: 's',
            type: FeedingType.bottle,
            startTime: base,
            isSnack: true,
          ),
        ),
        isFalse,
      );
    });
  });
}
