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
    test('rounds down to whole weeks', () {
      expect(at(DateTime(2026, 3, 29)), '2 weeks old');
      expect(at(DateTime(2026, 4, 4)), '2 weeks old');
      expect(at(DateTime(2026, 4, 5)), '3 weeks old');
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

    test('runs up to two years', () {
      expect(at(DateTime(2028, 2, 15)), '23 months old');
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
      // Born the 31st: the 28th of February is not yet a month later.
      final endOfMonth = DateTime(2026, 1, 31);
      expect(babyAgeLabel(endOfMonth, now: DateTime(2026, 2, 28)), '4 weeks old');
      expect(babyAgeLabel(endOfMonth, now: DateTime(2026, 3, 31)), '8 weeks old');
    });

    test('a leap day birthday still ages', () {
      final leap = DateTime(2028, 2, 29);
      expect(babyAgeLabel(leap, now: DateTime(2028, 8, 29)), '6 months old');
    });

    test('a birth date in the future says nothing rather than a negative', () {
      // A typo in the profile should not read as "-3 days old".
      expect(babyAgeLabel(DateTime(2026, 4, 1), now: DateTime(2026, 3, 15)), '');
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
