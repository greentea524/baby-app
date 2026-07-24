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
}
