import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/features/growth/growth_metric.dart';
import 'package:baby_app/features/growth/who_percentiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('whoPercentileCurves', () {
    test('returns the five standard percentiles, oldest month included', () {
      final curves = whoPercentileCurves(
        GrowthMetric.weight,
        BabySex.male,
        maxMonth: 12,
      );
      expect(curves.map((c) => c.label).toList(), [
        '3',
        '15',
        '50',
        '85',
        '97',
      ]);
      // Sampled at every whole month 0..12.
      expect(curves.first.points.length, 13);
      expect(curves.first.points.last.ageMonths, 12);
    });

    test('P50 equals the WHO median (M) at known ages', () {
      final curves = whoPercentileCurves(
        GrowthMetric.weight,
        BabySex.male,
        maxMonth: 12,
      );
      final p50 = curves.firstWhere((c) => c.label == '50').points;
      // WHO boys weight-for-age median: 3.3464 kg at birth, 9.6479 kg at 12mo.
      expect(p50[0].value, closeTo(3.3464, 0.001));
      expect(p50[12].value, closeTo(9.6479, 0.001));
    });

    test('percentiles are strictly ordered at a given age', () {
      final curves = whoPercentileCurves(
        GrowthMetric.height,
        BabySex.female,
        maxMonth: 6,
      );
      final atSix = curves.map((c) => c.points[6].value).toList();
      for (var i = 1; i < atSix.length; i++) {
        expect(atSix[i], greaterThan(atSix[i - 1]));
      }
    });

    test('clamps maxMonth to the 0–60 standard', () {
      final curves = whoPercentileCurves(
        GrowthMetric.head,
        BabySex.male,
        maxMonth: 999,
      );
      expect(curves.first.points.last.ageMonths, 60);
    });
  });

  group('whoPercentile', () {
    test('the WHO median reads as the 50th percentile', () {
      // Boys weight-for-age median at 12 months is 9.6479 kg.
      expect(
        whoPercentile(GrowthMetric.weight, BabySex.male, 12, 9.6479),
        closeTo(50, 0.1),
      );
    });

    test('round-trips the plotted reference curves', () {
      // Every curve value should map back to the percentile it was drawn for.
      final curves = whoPercentileCurves(
        GrowthMetric.weight,
        BabySex.male,
        maxMonth: 12,
      );
      for (final c in curves) {
        final point = c.points[12];
        expect(
          whoPercentile(GrowthMetric.weight, BabySex.male, 12, point.value),
          closeTo(double.parse(c.label), 0.1),
          reason: 'curve ${c.label} should round-trip',
        );
      }
    });

    test('rises with the measured value at a fixed age', () {
      final low = whoPercentile(GrowthMetric.weight, BabySex.female, 6, 6.0)!;
      final high = whoPercentile(GrowthMetric.weight, BabySex.female, 6, 8.5)!;
      expect(high, greaterThan(low));
    });

    test('interpolates between whole months', () {
      // Mid-month sits between the two neighbouring medians, so a fixed
      // value yields a percentile between the two whole-month answers.
      final at6 = whoPercentile(GrowthMetric.weight, BabySex.male, 6, 8.0)!;
      final at7 = whoPercentile(GrowthMetric.weight, BabySex.male, 7, 8.0)!;
      final at6h = whoPercentile(GrowthMetric.weight, BabySex.male, 6.5, 8.0)!;
      expect(at6h, lessThan(at6));
      expect(at6h, greaterThan(at7));
    });

    test('returns null outside the reference range', () {
      // Beyond the 0–60 month standard, and for non-positive values.
      expect(whoPercentile(GrowthMetric.weight, BabySex.male, 61, 20), isNull);
      expect(whoPercentile(GrowthMetric.weight, BabySex.male, -1, 5), isNull);
      expect(whoPercentile(GrowthMetric.weight, BabySex.male, 6, 0), isNull);
    });
  });

  group('percentileLabel', () {
    test('uses the right ordinal suffix', () {
      expect(percentileLabel(62), '62nd percentile');
      expect(percentileLabel(21), '21st percentile');
      expect(percentileLabel(3), '3rd percentile');
      expect(percentileLabel(40), '40th percentile');
    });

    test('teens always take "th"', () {
      expect(percentileLabel(11), '11th percentile');
      expect(percentileLabel(12), '12th percentile');
      expect(percentileLabel(13), '13th percentile');
    });

    test('clamps the tails rather than showing false precision', () {
      expect(percentileLabel(0.3), '<1st percentile');
      expect(percentileLabel(99.8), '>99th percentile');
    });
  });
}
