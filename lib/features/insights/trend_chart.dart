import 'package:flutter/material.dart';

/// A compact bar chart of one metric across a date range (KAN-166).
///
/// Hand-painted for the same reason as the growth chart: it keeps the app
/// dependency-free and the bars are simple enough not to warrant a library.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 160,
    this.valueFormat,
  });

  /// One value per day, earliest first. Days with no activity are zeros.
  final List<double> values;

  /// One label per value. As many are drawn as fit without overlapping,
  /// always including the last day.
  final List<String> labels;

  final double height;

  /// Formats the y-axis ticks. Defaults to a trimmed number.
  final String Function(double)? valueFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (values.isEmpty || values.every((v) => v == 0)) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Nothing logged in this range.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _TrendChartPainter(
          values: values,
          labels: labels,
          bar: theme.colorScheme.primary,
          grid: theme.colorScheme.outlineVariant,
          text: theme.colorScheme.onSurfaceVariant,
          format: valueFormat ?? _trim,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.values,
    required this.labels,
    required this.bar,
    required this.grid,
    required this.text,
    required this.format,
  });

  final List<double> values;
  final List<String> labels;
  final Color bar;
  final Color grid;
  final Color text;
  final String Function(double) format;

  static const _leftPad = 36.0;
  static const _bottomPad = 20.0;
  static const _topPad = 10.0;
  static const _rightPad = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _leftPad,
      _topPad,
      size.width - _rightPad,
      size.height - _bottomPad,
    );

    final maxValue = values.reduce((a, b) => a > b ? a : b);
    // Round the top of the scale up so gridlines land on tidy numbers.
    final top = maxValue <= 0 ? 1.0 : maxValue * 1.1;

    const yTicks = 3;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= yTicks; i++) {
      final value = top * i / yTicks;
      final y = plot.bottom - plot.height * i / yTicks;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _label(
        canvas,
        format(value),
        Offset(plot.left - 5, y),
        anchorRight: true,
      );
    }

    // Bars: one slot per day, with a small gap between them.
    final slot = plot.width / values.length;
    final barWidth = (slot * 0.7).clamp(1.0, 18.0);
    final barPaint = Paint()..color = bar;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final h = plot.height * (values[i] / top);
      final cx = plot.left + slot * (i + 0.5);
      final rect = Rect.fromLTWH(
        cx - barWidth / 2,
        plot.bottom - h,
        barWidth,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        barPaint,
      );
    }

    // X labels: as many as fit without colliding, rather than a fixed three.
    // Measure a real label instead of guessing — "12/31" is wider than "7/4",
    // and the widest one is what decides the spacing.
    if (labels.isEmpty) return;
    final widest = labels.map(_measure).reduce((a, b) => a > b ? a : b);
    const gap = 10.0;
    final fits = (plot.width / (widest + gap)).floor().clamp(1, labels.length);
    final step = (labels.length / fits).ceil();

    // Walk back from the last day so the end of the range is always labelled
    // — that's the one people look for — then step evenly backwards.
    final marks = <int>{};
    for (var i = labels.length - 1; i >= 0; i -= step) {
      marks.add(i);
    }
    for (final i in marks) {
      if (i >= labels.length) continue;
      _label(
        canvas,
        labels[i],
        Offset(plot.left + slot * (i + 0.5), plot.bottom + 4),
        centerX: true,
      );
    }
  }

  /// Rendered width of [text] at the label style.
  double _measure(String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  void _label(
    Canvas canvas,
    String value,
    Offset at, {
    bool anchorRight = false,
    bool centerX = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: text, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (anchorRight) dx -= tp.width;
    if (centerX) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_TrendChartPainter old) =>
      old.values != values || old.bar != bar;
}
