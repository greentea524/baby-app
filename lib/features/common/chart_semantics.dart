/// Spoken descriptions of the hand-painted charts (#24).
///
/// A `CustomPaint` tells assistive technology nothing at all, so both charts
/// were a large silent rectangle. The numbers were on screen the whole time —
/// the trend chart already captions a tapped bar — but only reachable by
/// hitting the right pixels, which is the one thing a screen-reader user
/// cannot do.
///
/// Pure string building, kept away from the painters so it can be read and
/// tested as prose. Everything here is written to be *heard*: commas where a
/// pause helps, no symbols that read badly aloud, and the shape of the data
/// before its extremes, because that is the order someone needs it in.
library;

/// A one-sentence account of a bar chart: what it is, how much of it there
/// is, and where the high and low points sit.
///
/// [format] is the chart's own value formatter, so the summary says "6h 15m"
/// where the caption would.
String barChartSummary({
  required String title,
  required List<double> values,
  required List<String> labels,
  required String Function(double) format,
  String? subtitle,
}) {
  final opening = subtitle == null ? title : '$title, $subtitle';
  if (values.isEmpty) return '$opening. Nothing logged.';
  if (values.every((v) => v == 0)) return '$opening. Nothing logged.';

  var highest = 0;
  var lowest = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[highest]) highest = i;
    if (values[i] < values[lowest]) lowest = i;
  }

  final parts = <String>[
    '$opening. Bar chart, ${values.length} '
        '${values.length == 1 ? 'bar' : 'bars'}',
    'highest ${format(values[highest])} at ${_spoken(labels, highest)}',
  ];
  // A flat chart has no low point worth naming, and saying the same number
  // twice sounds like a mistake rather than a fact.
  if (values[lowest] != values[highest]) {
    parts.add('lowest ${format(values[lowest])} at ${_spoken(labels, lowest)}');
  }
  return '${parts.join(', ')}.';
}

/// A one-sentence account of the growth line: how many measurements, over
/// what age span, and from what to what.
String growthChartSummary({
  required String metric,
  required String unit,
  required List<({double ageMonths, double value})> points,
  bool hasPercentiles = false,
}) {
  if (points.isEmpty) return '$metric chart. Nothing logged.';

  final first = points.first;
  final last = points.last;
  final reference = hasPercentiles
      ? ', with WHO percentile curves from the 3rd to the 97th'
      : '';

  if (points.length == 1) {
    return '$metric chart. One measurement, '
        '${_number(first.value)} $unit at ${_months(first.ageMonths)}'
        '$reference.';
  }
  return '$metric chart. ${points.length} measurements, from '
      '${_number(first.value)} $unit at ${_months(first.ageMonths)} '
      'to ${_number(last.value)} $unit at ${_months(last.ageMonths)}'
      '$reference.';
}

/// What one point on the growth line is worth, for a reader moving through
/// them one at a time.
String growthPointLabel({
  required double ageMonths,
  required double value,
  required String unit,
}) => '${_number(value)} $unit at ${_months(ageMonths)}';

/// The label for bar [i], or its position when the chart has none.
String _spoken(List<String> labels, int i) =>
    i < labels.length ? labels[i] : 'bar ${i + 1}';

/// Trims a trailing `.0` — "6.4" is worth hearing, "7.0" is not.
String _number(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "3 months", "0.5 months" — spelled out, because "3 mo" is read aloud as
/// the abbreviation rather than the word.
String _months(double months) {
  final rounded = _number(months);
  return '$rounded ${rounded == '1' ? 'month' : 'months'}';
}
