import 'package:flutter/material.dart';

import 'growth_metric.dart';
import 'who_percentiles.dart';

/// A line chart of the baby's measurements for one [metric] over age in
/// months (KAN-163), optionally overlaid with WHO percentile reference
/// curves ([curves], 3rd–97th) when the baby's sex is known.
class GrowthChart extends StatelessWidget {
  const GrowthChart({
    super.key,
    required this.points,
    required this.metric,
    this.curves = const [],
    this.height = 240,
  });

  final List<GrowthPoint> points;
  final GrowthMetric metric;
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
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _GrowthChartPainter(
          points: points,
          curves: curves,
          unit: metric.unit,
          line: theme.colorScheme.primary,
          band: theme.colorScheme.tertiary,
          grid: theme.colorScheme.outlineVariant,
          text: theme.colorScheme.onSurfaceVariant,
        ),
        child: const SizedBox.expand(),
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
  });

  final List<GrowthPoint> points;
  final List<PercentileCurve> curves;
  final String unit;
  final Color line;
  final Color band;
  final Color grid;
  final Color text;

  static const _leftPad = 40.0;
  static const _bottomPad = 24.0;
  static const _topPad = 12.0;
  static const _rightPad = 28.0; // room for percentile labels

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _leftPad,
      _topPad,
      size.width - _rightPad,
      size.height - _bottomPad,
    );

    // Bounds span the child's points and any reference curves.
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

    Offset toPixel(double x, double y) => Offset(
      plot.left + (x - minX) / (maxX - minX) * plot.width,
      plot.bottom - (y - minY) / (maxY - minY) * plot.height,
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
    const yTicks = 4;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= yTicks; i++) {
      final value = minY + (maxY - minY) * i / yTicks;
      final y = plot.bottom - plot.height * i / yTicks;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _label(
        canvas,
        value.toStringAsFixed(1),
        Offset(plot.left - 6, y),
        anchorRight: true,
      );
    }
    const xTicks = 4;
    for (var i = 0; i <= xTicks; i++) {
      final value = minX + (maxX - minX) * i / xTicks;
      final x = plot.left + plot.width * i / xTicks;
      _label(
        canvas,
        value.toStringAsFixed(value >= 10 ? 0 : 1),
        Offset(x, plot.bottom + 4),
        centerX: true,
      );
    }
    _label(
      canvas,
      'mo · $unit',
      Offset(plot.right, plot.bottom + 4),
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
      _label(
        canvas,
        c.label,
        toPixel(last.ageMonths, last.value) + const Offset(3, 0),
        fontSize: 8,
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

  void _label(
    Canvas canvas,
    String value,
    Offset at, {
    bool anchorRight = false,
    bool centerX = false,
    double fontSize = 10,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: text, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (anchorRight) dx -= tp.width;
    if (centerX) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_GrowthChartPainter old) =>
      old.points != points || old.curves != curves || old.line != line;
}
