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

/// The z-score of a measured [value] for an LMS triple — the inverse of
/// [_valueAtZ].
double _zScoreOf(LmsRow r, double value) {
  if (r.l.abs() < 1e-7) return math.log(value / r.m) / r.s;
  return (math.pow(value / r.m, r.l).toDouble() - 1) / (r.l * r.s);
}

/// The LMS triple at a fractional age, linearly interpolating between the
/// whole-month rows (measurements rarely land exactly on a month boundary).
/// Null when [ageMonths] falls outside the 0–60 month standard.
LmsRow? _lmsAt(List<LmsRow> series, double ageMonths) {
  final maxIndex = series.length - 1;
  if (ageMonths < 0 || ageMonths > maxIndex) return null;
  if (ageMonths == maxIndex) return series[maxIndex];
  final lo = ageMonths.floor();
  final t = ageMonths - lo;
  final a = series[lo];
  final b = series[lo + 1];
  return LmsRow(
    a.l + (b.l - a.l) * t,
    a.m + (b.m - a.m) * t,
    a.s + (b.s - a.s) * t,
  );
}

/// Abramowitz & Stegun 7.1.26 approximation of the error function
/// (|error| < 1.5e-7) — enough precision for a displayed percentile.
double _erf(double x) {
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;
  final sign = x.isNegative ? -1.0 : 1.0;
  final ax = x.abs();
  final t = 1 / (1 + p * ax);
  final y =
      1 -
      ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * math.exp(-ax * ax);
  return sign * y;
}

/// Standard normal CDF: the share of the population below [z].
double _normalCdf(double z) => 0.5 * (1 + _erf(z / math.sqrt2));

/// The WHO percentile (0–100) for a measured [value] of [metric] at
/// [ageMonths] for [sex] — e.g. 62.0 meaning "heavier than 62% of babies
/// this age". Null when there's no reference data, the age falls outside
/// the 0–60 month standard, or the value isn't positive.
double? whoPercentile(
  GrowthMetric metric,
  BabySex sex,
  double ageMonths,
  double value,
) {
  if (value <= 0) return null;
  final series = whoLms['${metric.name}_${sex.name}'];
  if (series == null) return null;
  final row = _lmsAt(series, ageMonths);
  if (row == null) return null;
  return _normalCdf(_zScoreOf(row, value)) * 100;
}

/// A percentile rendered for display: "62nd percentile", with the clinical
/// convention of clamping the tails to "<1st" / ">99th" rather than showing
/// a falsely precise 0.3 or 99.8.
String percentileLabel(double percentile) {
  if (percentile < 1) return '<1st percentile';
  if (percentile > 99) return '>99th percentile';
  final n = percentile.round();
  return '$n${_ordinalSuffix(n)} percentile';
}

String _ordinalSuffix(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return 'th';
  return switch (n % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
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
