import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/home/baby_age.dart';

/// The unit has to change with age, because "0 months" is not an answer for a
/// three-day-old and "26 months" is not how anyone says two years.
void main() {
  final born = DateTime(2026, 3, 15);
  String at(DateTime now) => babyAgeLabel(born, now: now);

  group('the first fortnight counts days', () {
    test('the day itself', () {
      expect(at(DateTime(2026, 3, 15)), 'born today');
    });

    test('singular, then plural', () {
      expect(at(DateTime(2026, 3, 16)), '1 day old');
      expect(at(DateTime(2026, 3, 20)), '5 days old');
      expect(at(DateTime(2026, 3, 28)), '13 days old');
    });

    test('the time of day does not age the baby', () {
      // Born in the evening, read the next morning: still one day, not two.
      final evening = DateTime(2026, 3, 15, 23, 30);
      expect(babyAgeLabel(evening, now: DateTime(2026, 3, 16, 7)), '1 day old');
    });
  });

  group('then weeks, while that is how appointments are counted', () {
    test('with the days since the last whole week', () {
      expect(at(DateTime(2026, 3, 29)), '2 weeks old');
      expect(at(DateTime(2026, 3, 30)), '2 weeks 1 day old');
      expect(at(DateTime(2026, 4, 4)), '2 weeks 6 days old');
      expect(at(DateTime(2026, 4, 5)), '3 weeks old');
    });

    test('so a week does not read as arriving early', () {
      // What was reported: "11 weeks" all week, even before the day it
      // turned. Born on a Sunday (15 Mar 2026), the Saturday before the
      // eleventh week is still ten weeks and six days.
      expect(at(DateTime(2026, 5, 30)), '10 weeks 6 days old');
      expect(at(DateTime(2026, 5, 31)), '11 weeks old');
      expect(at(DateTime(2026, 6, 1)), '11 weeks 1 day old');
    });

    test('holds until three months', () {
      // 15 Mar to 14 Jun is 91 days — thirteen weeks to the day, and still
      // one day short of the third month.
      expect(at(DateTime(2026, 6, 14)), '13 weeks old');
    });
  });

  group('then months', () {
    test('turns on the day of the month, not after an average', () {
      // Born the 15th, so the 14th has not turned over yet.
      expect(at(DateTime(2026, 6, 14)), '13 weeks old');
      expect(at(DateTime(2026, 6, 15)), '3 months old');
      expect(at(DateTime(2026, 10, 15)), '7 months old');
    });

    test('born on the 31st, on the last day of a shorter month', () {
      // Not on the 1st of the next: 30 June is four months after 28
      // February's turn, and 1 July would leave June with no anniversary.
      final late = DateTime(2026, 1, 31);
      expect(
        babyAgeLabel(late, now: DateTime(2026, 6, 29)),
        '4 months 4 weeks old',
      );
      expect(babyAgeLabel(late, now: DateTime(2026, 6, 30)), '5 months old');
      expect(
        babyAgeLabel(late, now: DateTime(2026, 7, 7)),
        '5 months 1 week old',
      );
      expect(babyAgeLabel(late, now: DateTime(2026, 7, 31)), '6 months old');
    });

    test('with the weeks since the month turned', () {
      expect(at(DateTime(2026, 7, 21)), '4 months old');
      expect(at(DateTime(2026, 7, 22)), '4 months 1 week old');
      expect(at(DateTime(2026, 8, 1)), '4 months 2 weeks old');
      expect(at(DateTime(2026, 8, 14)), '4 months 4 weeks old');
      expect(at(DateTime(2026, 8, 15)), '5 months old');
    });

    test('runs up to two years', () {
      expect(at(DateTime(2028, 2, 15)), '23 months old');
      // 2028 is a leap year: 15 Feb to 14 Mar is 28 days.
      expect(at(DateTime(2028, 3, 14)), '23 months 4 weeks old');
    });
  });

  group('then years', () {
    test('whole years read as years', () {
      expect(at(DateTime(2028, 3, 15)), '2 years old');
      expect(at(DateTime(2029, 3, 15)), '3 years old');
    });

    test('a part year keeps the months', () {
      expect(at(DateTime(2028, 6, 15)), '2y 3mo');
    });
  });

  group('awkward dates', () {
    test('a month shorter than the birth day has not turned over', () {
      // Born the 31st: still counted in weeks this early, so the weeks and
      // days are what show.
      final endOfMonth = DateTime(2026, 1, 31);
      expect(
        babyAgeLabel(endOfMonth, now: DateTime(2026, 2, 28)),
        '4 weeks old',
      );
      expect(
        // 59 days: still counted in weeks, two months not being three.
        babyAgeLabel(endOfMonth, now: DateTime(2026, 3, 31)),
        '8 weeks 3 days old',
      );
    });

    test('a leap day birthday still ages', () {
      final leap = DateTime(2028, 2, 29);
      expect(babyAgeLabel(leap, now: DateTime(2028, 8, 29)), '6 months old');
    });

    test('a birth date in the future says nothing rather than a negative', () {
      // A typo in the profile should not read as "-3 days old".
      expect(
        babyAgeLabel(DateTime(2026, 4, 1), now: DateTime(2026, 3, 15)),
        '',
      );
    });
  });

  test('a year of days never lands on an empty label', () {
    // Every day from birth to three years has to produce something readable.
    var day = born;
    for (var i = 0; i < 365 * 3; i++) {
      day = day.add(const Duration(days: 1));
      final label = babyAgeLabel(born, now: day);
      expect(label, isNotEmpty, reason: 'nothing to show on $day');
      expect(label, isNot(contains('-')), reason: 'negative age on $day');
    }
  });
}
