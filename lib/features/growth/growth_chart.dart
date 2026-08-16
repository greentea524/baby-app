import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/format/unit_system.dart';
import '../common/chart_semantics.dart';
import '../common/chart_text.dart';
import 'growth_metric.dart';
import 'who_percentiles.dart';

/// A line chart of the baby's measurements for one [metric] over age in
/// months (KAN-163), optionally overlaid with WHO percentile reference
/// curves ([curves], 3rd–97th) when the baby's sex is known.
///
/// Announces itself and each measurement to a screen reader, and its axis
/// labels follow the reader's text size (#24).
class GrowthChart extends StatelessWidget {
  const GrowthChart({
    super.key,
    required this.points,
    required this.metric,
    required this.units,
    this.curves = const [],
    this.height = 240,
  });

  final List<GrowthPoint> points;
  final GrowthMetric metric;
  final UnitSystem units;
  final List<PercentileCurve> curves;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Log a ${metric.label.toLowerCase()} measurement to see the chart.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // Convert stored (metric) values to US-customary units for the axis.
    List<GrowthPoint> toDisplay(List<GrowthPoint> pts) => [
      for (final p in pts)
        (ageMonths: p.ageMonths, value: metric.toDisplay(p.value, units)),
    ];

    final shown = toDisplay(points);
    final unit = metric.displayUnit(units);
    final text = ChartText.of(
      context,
      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
    );

    return SizedBox(
      height: height,
      child: Semantics(
        label: growthChartSummary(
          metric: metric.label,
          unit: unit,
          points: shown,
          hasPercentiles: curves.length >= 2,
        ),
        explicitChildNodes: true,
        child: CustomPaint(
          painter: _GrowthChartPainter(
            points: shown,
            curves: [
              for (final c in curves)
                (label: c.label, points: toDisplay(c.points)),
            ],
            unit: unit,
            line: theme.colorScheme.primary,
            band: theme.colorScheme.tertiary,
            grid: theme.colorScheme.outlineVariant,
            text: text,
            // The percentile labels sit inside the plot against the curves,
            // so they stay a size down from the axis.
            small: ChartText(
              style: text.style.copyWith(fontSize: 8),
              scaler: text.scaler,
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _GrowthChartPainter extends CustomPainter {
  _GrowthChartPainter({
    required this.points,
    required this.curves,
    required this.unit,
    required this.line,
    required this.band,
    required this.grid,
    required this.text,
    required this.small,
  });

  final List<GrowthPoint> points;
  final List<PercentileCurve> curves;
  final String unit;
  final Color line;
  final Color band;
  final Color grid;
  final ChartText text;
  final ChartText small;

  static const _yTicks = 4;
  static const _xTicks = 4;

  /// Room above the plot for the "mo · unit" caption, which sits there rather
  /// than on the x-axis. It used to be drawn anchored to the bottom-right
  /// corner — the same spot the last x tick is centred on, so the two were
  /// always overlapping and a larger text size only made it more obvious.
  double get _topPad => text.lineHeight + 6;

  /// The plot rectangle, with gutters sized to the labels that go in them
  /// rather than to constants — at a larger text size the old fixed 40px
  /// left gutter clipped the axis (#24).
  Rect _plot(Size size, _Bounds b) {
    final leftPad = text.widest(_yLabels(b)) + 10;
    // The right edge carries the percentile labels, which are drawn just
    // inside it, plus the "mo · unit" caption.
    final rightPad = curves.isEmpty
        ? 8.0
        : small.widest(curves.map((c) => c.label)) + 8;
    return Rect.fromLTRB(
      leftPad,
      _topPad,
      size.width - rightPad,
      size.height - (text.lineHeight + 12),
    );
  }

  List<String> _yLabels(_Bounds b) => [
    for (var i = 0; i <= _yTicks; i++)
      (b.minY + (b.maxY - b.minY) * i / _yTicks).toStringAsFixed(1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final b = _Bounds.of(points, curves);
    final plot = _plot(size, b);

    Offset toPixel(double x, double y) => Offset(
      plot.left + (x - b.minX) / (b.maxX - b.minX) * plot.width,
      plot.bottom - (y - b.minY) / (b.maxY - b.minY) * plot.height,
    );

    // Shaded band between the outermost percentiles (3rd–97th).
    if (curves.length >= 2) {
      final low = curves.first.points;
      final high = curves.last.points;
      final fill = Path()
        ..moveTo(
          toPixel(high.first.ageMonths, high.first.value).dx,
          toPixel(high.first.ageMonths, high.first.value).dy,
        );
      for (final p in high.skip(1)) {
        final o = toPixel(p.ageMonths, p.value);
        fill.lineTo(o.dx, o.dy);
      }
      for (final p in low.reversed) {
        final o = toPixel(p.ageMonths, p.value);
        fill.lineTo(o.dx, o.dy);
      }
      fill.close();
      canvas.drawPath(fill, Paint()..color = band.withValues(alpha: 0.08));
    }

    // Gridlines + y labels.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final yLabels = _yLabels(b);
    for (var i = 0; i <= _yTicks; i++) {
      final y = plot.bottom - plot.height * i / _yTicks;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      text.paint(
        canvas,
        yLabels[i],
        Offset(plot.left - 6, y),
        anchorRight: true,
      );
    }
    for (var i = 0; i <= _xTicks; i++) {
      final value = b.minX + (b.maxX - b.minX) * i / _xTicks;
      final x = plot.left + plot.width * i / _xTicks;
      text.paint(
        canvas,
        value.toStringAsFixed(value >= 10 ? 0 : 1),
        Offset(x, plot.bottom + 4),
        centerX: true,
      );
    }
    text.paint(
      canvas,
      'mo · $unit',
      Offset(plot.right, plot.top - text.lineHeight / 2 - 3),
      anchorRight: true,
    );

    // Percentile reference lines + right-edge labels.
    final curvePaint = Paint()
      ..color = band.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final c in curves) {
      final path = Path();
      for (var i = 0; i < c.points.length; i++) {
        final o = toPixel(c.points[i].ageMonths, c.points[i].value);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, curvePaint);
      final last = c.points.last;
      small.paint(
        canvas,
        c.label,
        toPixel(last.ageMonths, last.value) + const Offset(3, 0),
      );
    }

    // Child line + dots on top.
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = toPixel(points[i].ageMonths, points[i].value);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, linePaint);
    final dotPaint = Paint()..color = line;
    for (final p in points) {
      canvas.drawCircle(toPixel(p.ageMonths, p.value), 3.5, dotPaint);
    }
  }

  /// One node per measurement, sized to a comfortable target around the dot
  /// rather than to the 3.5px dot itself.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final b = _Bounds.of(points, curves);
    final plot = _plot(size, b);
    return [
      for (final p in points)
        CustomPainterSemantics(
          rect: Rect.fromCenter(
            center: Offset(
              plot.left +
                  (p.ageMonths - b.minX) / (b.maxX - b.minX) * plot.width,
              plot.bottom -
                  (p.value - b.minY) / (b.maxY - b.minY) * plot.height,
            ),
            width: 24,
            height: 24,
          ),
          properties: SemanticsProperties(
            label: growthPointLabel(
              ageMonths: p.ageMonths,
              value: p.value,
              unit: unit,
            ),
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRepaint(_GrowthChartPainter old) =>
      old.points != points ||
      old.curves != curves ||
      old.line != line ||
      old.text != text;

  @override
  bool shouldRebuildSemantics(_GrowthChartPainter old) =>
      old.points != points || old.unit != unit;
}

/// The value ranges the plot has to cover, padded so the line is not drawn
/// against the edges.
class _Bounds {
  const _Bounds(this.minX, this.maxX, this.minY, this.maxY);

  factory _Bounds.of(List<GrowthPoint> points, List<PercentileCurve> curves) {
    final allX = <double>[
      for (final p in points) p.ageMonths,
      for (final c in curves) ...c.points.map((p) => p.ageMonths),
    ];
    final allY = <double>[
      for (final p in points) p.value,
      for (final c in curves) ...c.points.map((p) => p.value),
    ];
    var minX = allX.reduce((a, b) => a < b ? a : b);
    var maxX = allX.reduce((a, b) => a > b ? a : b);
    var minY = allY.reduce((a, b) => a < b ? a : b);
    var maxY = allY.reduce((a, b) => a > b ? a : b);

    if (maxX - minX < 0.5) {
      minX -= 1;
      maxX += 1;
    }
    if (maxY - minY < 0.5) {
      minY -= 1;
      maxY += 1;
    } else {
      final margin = (maxY - minY) * 0.08;
      minY -= margin;
      maxY += margin;
    }
    if (minX < 0) minX = 0;
    return _Bounds(minX, maxX, minY, maxY);
  }

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}
