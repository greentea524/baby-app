import 'dart:math' as math;

import '../../data/models/baby.dart';
import 'growth_metric.dart';
import 'who_lms_data.dart';

/// WHO percentiles rendered on the growth chart, with the z-score each maps
/// to. WHO growth charts conventionally show the 3rd/15th/50th/85th/97th.
const _percentiles = <({String label, double z})>[
  (label: '3', z: -1.88079),
  (label: '15', z: -1.03643),
  (label: '50', z: 0),
  (label: '85', z: 1.03643),
  (label: '97', z: 1.88079),
];

/// A named reference curve sampled at integer months.
typedef PercentileCurve = ({String label, List<GrowthPoint> points});

/// The measured value at [z] standard deviations for an LMS triple, using the
/// standard LMS transform: X = M·(1 + L·S·z)^(1/L), or M·e^(S·z) when L≈0.
double _valueAtZ(LmsRow r, double z) {
  if (r.l.abs() < 1e-7) return r.m * math.exp(r.s * z);
  return r.m * math.pow(1 + r.l * r.s * z, 1 / r.l).toDouble();
}

/// WHO reference percentile curves for [metric] and [sex], sampled at each
/// whole month from 0 to [maxMonth] (clamped to the 0–60 month standard).
/// Empty if no reference data exists for the combination.
List<PercentileCurve> whoPercentileCurves(
  GrowthMetric metric,
  BabySex sex, {
  required int maxMonth,
}) {
  final series = whoLms['${metric.name}_${sex.name}'];
  if (series == null) return const [];
  final end = maxMonth.clamp(0, series.length - 1);
  return [
    for (final p in _percentiles)
      (
        label: p.label,
        points: [
          for (var m = 0; m <= end; m++)
            (ageMonths: m.toDouble(), value: _valueAtZ(series[m], p.z)),
        ],
      ),
  ];
}
