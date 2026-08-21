import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/insights/day_view_data.dart';

/// One day's worth of events, arranged for reading rather than counting.
void main() {
  final day = DateTime(2026, 8, 20);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 8, 20, hour, minute);

  FeedingEvent feed(DateTime t, {bool snack = false}) => FeedingEvent(
    id: 'f$t',
    type: FeedingType.bottle,
    startTime: t,
    isSnack: snack,
  );
  DiaperEvent diaper(DateTime t, DiaperType type) =>
      DiaperEvent(id: 'd$t', type: type, time: t);

  group('placing events on the day', () {
    test('an event lands on the hour it happened', () {
      final marks = dayMarks(day: day, feedings: [feed(at(13, 30))]);
      expect(marks.single.hour, closeTo(13.5, 1e-9));
    });

    test('midnight is zero and the last minute is just under 24', () {
      final marks = dayMarks(
        day: day,
        feedings: [feed(at(0)), feed(at(23, 59))],
      );
      expect(marks.first.hour, 0);
      expect(marks.last.hour, lessThan(24));
    });

    test('everything is sorted, whatever order it arrived in', () {
      final marks = dayMarks(
        day: day,
        feedings: [feed(at(18)), feed(at(6))],
        diapers: [diaper(at(12), DiaperType.wet)],
      );
      expect([for (final m in marks) m.hour], [6, 12, 18]);
    });

    test('another day is dropped, not pinned to an edge', () {
      // A mark at 00:00 that really happened yesterday would read as a real
      // event at midnight, which is the one hour you want to trust.
      final marks = dayMarks(
        day: day,
        feedings: [
          feed(at(0).subtract(const Duration(minutes: 1))),
          feed(at(23, 59).add(const Duration(minutes: 2))),
          feed(at(9)),
        ],
      );
      expect(marks.single.hour, 9);
    });

    test('each kind keeps its own identity', () {
      final marks = dayMarks(
        day: day,
        feedings: [feed(at(1)), feed(at(2), snack: true)],
        diapers: [diaper(at(3), DiaperType.dirty)],
        pumps: [PumpingEvent(id: 'p1', time: at(4))],
      );
      expect(
        [for (final m in marks) m.kind],
        [
          DayMarkKind.feed,
          DayMarkKind.snack,
          DayMarkKind.diaper,
          DayMarkKind.pump,
        ],
      );
    });

    test('a day with nothing in it is empty, not zero-filled', () {
      expect(dayMarks(day: day), isEmpty);
    });
  });

  group('what was in the diapers', () {
    test('counts each type', () {
      final mix = diaperMix([
        diaper(at(1), DiaperType.wet),
        diaper(at(2), DiaperType.wet),
        diaper(at(3), DiaperType.dirty),
        diaper(at(4), DiaperType.both),
      ]);
      expect(mix, (wet: 2, dirty: 1, both: 1));
      expect(mix.total, 4);
    });

    test('a mixed diaper counts as a poo', () {
      // The question is "has there been one today", and a mixed diaper is a
      // dirty one that also happened to be wet.
      final mix = diaperMix([diaper(at(1), DiaperType.both)]);
      expect(mix.withPoop, 1);
    });

    test('a day of wet only has none', () {
      final mix = diaperMix([
        diaper(at(1), DiaperType.wet),
        diaper(at(2), DiaperType.wet),
      ]);
      expect(mix.withPoop, 0);
      expect(mix.total, 2);
    });

    test('no diapers at all', () {
      expect(diaperMix(const []), (wet: 0, dirty: 0, both: 0));
    });
  });

  group('the last one that counted', () {
    test('finds the most recent, across days', () {
      // Deliberately not limited to today: "none yet" means something very
      // different at 6am than at 6pm, and the difference is when the last
      // one was.
      final yesterday = at(21).subtract(const Duration(days: 1));
      final found = lastWithPoop([
        diaper(yesterday, DiaperType.dirty),
        diaper(yesterday.subtract(const Duration(hours: 5)), DiaperType.both),
        diaper(at(8), DiaperType.wet),
      ]);
      expect(found?.time, yesterday);
    });

    test('ignores wet ones entirely', () {
      expect(
        lastWithPoop([
          diaper(at(8), DiaperType.wet),
          diaper(at(14), DiaperType.wet),
        ]),
        isNull,
      );
    });

    test('null when there is nothing to find', () {
      expect(lastWithPoop(const []), isNull);
    });

    test('does not assume the list is sorted', () {
      final found = lastWithPoop([
        diaper(at(6), DiaperType.dirty),
        diaper(at(18), DiaperType.both),
        diaper(at(11), DiaperType.dirty),
      ]);
      expect(found?.time, at(18));
    });
  });
}
