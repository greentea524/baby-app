import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/chart_semantics.dart';

/// What the charts say out loud (#24).
///
/// A `CustomPaint` announces nothing at all, so both charts were a silent
/// rectangle to a screen reader. These are the sentences that replace the
/// silence, and they are worth reading as prose — the test is as much about
/// whether they make sense heard as whether the numbers are right.
void main() {
  group('a bar chart', () {
    String summarise({
      String title = 'Feeds per day',
      String? subtitle,
      List<double> values = const [4, 7, 2],
      List<String> labels = const ['Jul 1', 'Jul 2', 'Jul 3'],
      String Function(double)? format,
    }) => barChartSummary(
      title: title,
      subtitle: subtitle,
      values: values,
      labels: labels,
      format: format ?? (v) => v.toStringAsFixed(0),
    );

    test('says what it is, how big it is, and where the extremes are', () {
      expect(
        summarise(),
        'Feeds per day. Bar chart, 3 bars, highest 7 at Jul 2, '
        'lowest 2 at Jul 3.',
      );
    });

    test('carries the subtitle, which is where the window is explained', () {
      // "Longest night stretch" alone does not say what counts as night.
      expect(
        summarise(
          title: 'Longest night stretch',
          subtitle: 'Between milk feeds, 7p–7a',
        ),
        startsWith('Longest night stretch, Between milk feeds, 7p–7a. '),
      );
    });

    test('speaks the value the caption would, not the raw number', () {
      expect(
        summarise(
          values: [375, 400],
          labels: ['Jul 1', 'Jul 2'],
          format: (v) => '${v ~/ 60}h ${(v % 60).toInt()}m',
        ),
        contains('highest 6h 40m at Jul 2'),
      );
    });

    test('does not name a low point on a flat chart', () {
      // Saying "highest 5, lowest 5" sounds like a mistake being made rather
      // than a fact being stated.
      final flat = summarise(values: [5, 5, 5]);
      expect(flat, contains('highest 5'));
      expect(flat, isNot(contains('lowest')));
    });

    test('an empty day is a low point, because that is what it was', () {
      expect(summarise(values: [4, 0, 2]), contains('lowest 0 at Jul 2'));
    });

    test('says nothing was logged rather than reading out zeros', () {
      expect(summarise(values: [0, 0, 0]), 'Feeds per day. Nothing logged.');
      expect(
        summarise(values: [], labels: []),
        'Feeds per day. Nothing logged.',
      );
    });

    test('counts one bar as a bar', () {
      expect(summarise(values: [5], labels: ['Jul 1']), contains('1 bar,'));
    });

    test('falls back to a position when a label is missing', () {
      // Guards against an out-of-range read rather than promising a nice
      // sentence: the two lists should always be the same length.
      expect(summarise(values: [1, 9], labels: ['Jul 1']), contains('bar 2'));
    });
  });

  group('a growth chart', () {
    test('says how many measurements, and from what to what', () {
      expect(
        growthChartSummary(
          metric: 'Weight',
          unit: 'kg',
          points: [
            (ageMonths: 0, value: 3.4),
            (ageMonths: 2.5, value: 5.1),
            (ageMonths: 6, value: 7),
          ],
        ),
        'Weight chart. 3 measurements, from 3.4 kg at 0 months '
        'to 7 kg at 6 months.',
      );
    });

    test('mentions the reference curves when they are drawn', () {
      expect(
        growthChartSummary(
          metric: 'Weight',
          unit: 'kg',
          points: [(ageMonths: 0, value: 3.4), (ageMonths: 6, value: 7)],
          hasPercentiles: true,
        ),
        endsWith('with WHO percentile curves from the 3rd to the 97th.'),
      );
    });

    test('reads sensibly with a single measurement', () {
      // "from 3.4 kg to 3.4 kg" would be the obvious bug here.
      expect(
        growthChartSummary(
          metric: 'Height',
          unit: 'cm',
          points: [(ageMonths: 1, value: 54.2)],
        ),
        'Height chart. One measurement, 54.2 cm at 1 month.',
      );
    });

    test('says nothing was logged for an empty chart', () {
      expect(
        growthChartSummary(metric: 'Weight', unit: 'kg', points: []),
        'Weight chart. Nothing logged.',
      );
    });

    test('a point reads as a measurement at an age', () {
      expect(
        growthPointLabel(ageMonths: 3.5, value: 6.25, unit: 'kg'),
        '6.3 kg at 3.5 months',
      );
      // Singular where it matters — "1 months" is the giveaway of a string
      // built without listening to it.
      expect(
        growthPointLabel(ageMonths: 1, value: 5, unit: 'kg'),
        '5 kg at 1 month',
      );
    });
  });
}
