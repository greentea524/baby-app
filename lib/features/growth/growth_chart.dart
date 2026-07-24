import 'package:flutter/material.dart';

import 'growth_metric.dart';

/// A simple line chart of the baby's own measurements for one [metric] over
/// age in months (KAN-163). WHO/CDC percentile reference bands are a planned
/// enhancement (needs the baby's sex + official LMS tables).
class GrowthChart extends StatelessWidget {
  const GrowthChart({
    super.key,
    required this.points,
    required this.metric,
    this.height = 220,
  });

  final List<GrowthPoint> points;
  final GrowthMetric metric;
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
          unit: metric.unit,
          line: theme.colorScheme.primary,
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
    required this.unit,
    required this.line,
    required this.grid,
    required this.text,
  });

  final List<GrowthPoint> points;
  final String unit;
  final Color line;
  final Color grid;
  final Color text;

  static const _leftPad = 40.0;
  static const _bottomPad = 24.0;
  static const _topPad = 12.0;
  static const _rightPad = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _leftPad,
      _topPad,
      size.width - _rightPad,
      size.height - _bottomPad,
    );

    var minX = points.first.ageMonths;
    var maxX = points.last.ageMonths;
    var minY = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    var maxY = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    // Pad degenerate ranges so a single point still renders sensibly.
    if (maxX - minX < 0.5) {
      minX -= 1;
      maxX += 1;
    }
    if (maxY - minY < 0.5) {
      minY -= 1;
      maxY += 1;
    } else {
      final margin = (maxY - minY) * 0.1;
      minY -= margin;
      maxY += margin;
    }
    if (minX < 0) minX = 0;

    Offset toPixel(double x, double y) => Offset(
      plot.left + (x - minX) / (maxX - minX) * plot.width,
      plot.bottom - (y - minY) / (maxY - minY) * plot.height,
    );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // Horizontal gridlines + y labels.
    const yTicks = 4;
    for (var i = 0; i <= yTicks; i++) {
      final value = minY + (maxY - minY) * i / yTicks;
      final y = plot.bottom - plot.height * i / yTicks;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _label(
        canvas,
        value.toStringAsFixed(1),
        Offset(plot.left - 6, y),
        align: TextAlign.right,
        anchorRight: true,
      );
    }

    // Vertical x labels (age in months).
    const xTicks = 4;
    for (var i = 0; i <= xTicks; i++) {
      final value = minX + (maxX - minX) * i / xTicks;
      final x = plot.left + plot.width * i / xTicks;
      _label(
        canvas,
        value.toStringAsFixed(value >= 10 ? 0 : 1),
        Offset(x, plot.bottom + 4),
        align: TextAlign.center,
        centerX: true,
      );
    }
    _label(
      canvas,
      'mo · $unit',
      Offset(plot.right, plot.bottom + 4),
      align: TextAlign.right,
      anchorRight: true,
    );

    // Data line.
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = toPixel(points[i].ageMonths, points[i].value);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // Data dots.
    final dotPaint = Paint()..color = line;
    for (final p in points) {
      canvas.drawCircle(toPixel(p.ageMonths, p.value), 3.5, dotPaint);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    required TextAlign align,
    bool anchorRight = false,
    bool centerX = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: this.text, fontSize: 10),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (anchorRight) dx -= tp.width;
    if (centerX) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_GrowthChartPainter old) =>
      old.points != points || old.line != line;
}
