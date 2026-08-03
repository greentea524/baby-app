import 'package:flutter/material.dart';

/// A compact bar chart of one metric across a date range (KAN-166).
///
/// Hand-painted for the same reason as the growth chart: it keeps the app
/// dependency-free and the bars are simple enough not to warrant a library.
///
/// Tap a bar to read its day and value. The bars are only a few pixels wide on
/// a month range and carry no labels of their own, so without this the chart
/// showed a shape you could not interrogate — the numbers behind it were only
/// available by exporting.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 160,
    this.valueFormat,
    this.axisFormat,
    this.secondaryFormat,
  });

  /// One value per day, earliest first. Days with no activity are zeros.
  final List<double> values;

  /// One label per value. As many are drawn as fit without overlapping,
  /// always including the last day.
  final List<String> labels;

  final double height;

  /// Formats the value wherever it is shown. Defaults to a trimmed number.
  final String Function(double)? valueFormat;

  /// Formats the y-axis ticks alone, for when [valueFormat] is too wide for
  /// the 36 px gutter. A duration is the case in point: "13h 12m" overruns the
  /// axis, but shortening the tapped value to "13.2h" would throw away
  /// precision the caption has room for. Defaults to [valueFormat].
  final String Function(double)? axisFormat;

  /// When set, draws a second set of tick labels down the right edge —
  /// used to read the same bars in a second unit without a second chart.
  final String Function(double)? secondaryFormat;

  static String trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _selected;

  @override
  void didUpdateWidget(TrendChart old) {
    super.didUpdateWidget(old);
    // The selection indexes into the old range; keeping it would caption a day
    // that is no longer plotted.
    if (old.values != widget.values) _selected = null;
  }

  void _handleTap(Offset at, Size size) {
    final geometry = TrendGeometry(
      count: widget.values.length,
      hasSecondary: widget.secondaryFormat != null,
    );
    setState(() => _selected = geometry.indexAt(at, size));
  }

  /// "Jul 4 · 240 ml (8.1 fl oz)" — what the tapped bar is worth.
  String _describe(int i) {
    final format = widget.valueFormat ?? TrendChart.trim;
    final value = format(widget.values[i]);
    final second = widget.secondaryFormat;
    final suffix = second == null ? '' : ' (${second(widget.values[i])})';
    return '${widget.labels[i]} · $value$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.values.isEmpty || widget.values.every((v) => v == 0)) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Nothing logged in this range.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, widget.height);
              return GestureDetector(
                onTapUp: (d) => _handleTap(d.localPosition, size),
                child: CustomPaint(
                  painter: _TrendChartPainter(
                    values: widget.values,
                    labels: widget.labels,
                    selected: selected,
                    bar: theme.colorScheme.primary,
                    highlight: theme.colorScheme.tertiary,
                    grid: theme.colorScheme.outlineVariant,
                    text: theme.colorScheme.onSurfaceVariant,
                    format:
                        widget.axisFormat ??
                        widget.valueFormat ??
                        TrendChart.trim,
                    secondary: widget.secondaryFormat,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // The caption doubles as the tooltip: the bars are too narrow to label
        // individually, and a tap target that reveals nothing is worse than
        // none.
        Text(
          selected == null ? 'Tap a bar for details' : _describe(selected),
          style: theme.textTheme.bodySmall?.copyWith(
            color: selected == null
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
            fontWeight: selected == null ? null : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Where the plot sits inside the chart, shared by the painter and the hit
/// test so a tap lands on the bar it looks like it landed on.
class TrendGeometry {
  const TrendGeometry({required this.count, required this.hasSecondary});

  final int count;
  final bool hasSecondary;

  static const leftPad = 36.0;
  static const bottomPad = 20.0;
  static const topPad = 10.0;

  /// Room for the second unit's labels when there is one.
  double get rightPad => hasSecondary ? 34.0 : 8.0;

  Rect plot(Size size) => Rect.fromLTRB(
    leftPad,
    topPad,
    size.width - rightPad,
    size.height - bottomPad,
  );

  /// The day at [at], or null outside the plot.
  ///
  /// Matches on the whole column rather than the drawn bar: bars are as narrow
  /// as a pixel on a month range, and a target you have to hit exactly is not
  /// one you can hit at all on a phone. Height is ignored for the same reason,
  /// so tapping the empty space above a short bar still selects its day.
  int? indexAt(Offset at, Size size) {
    if (count == 0) return null;
    final rect = plot(size);
    if (rect.width <= 0) return null;
    if (at.dx < rect.left || at.dx > rect.right) return null;

    final slot = rect.width / count;
    final index = ((at.dx - rect.left) / slot).floor();
    return index < 0 || index >= count ? null : index;
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.values,
    required this.labels,
    required this.selected,
    required this.bar,
    required this.highlight,
    required this.grid,
    required this.text,
    required this.format,
    this.secondary,
  });

  final List<double> values;
  final List<String> labels;
  final int? selected;
  final Color bar;
  final Color highlight;
  final Color grid;
  final Color text;
  final String Function(double) format;
  final String Function(double)? secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = TrendGeometry(
      count: values.length,
      hasSecondary: secondary != null,
    );
    final plot = geometry.plot(size);

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
      if (secondary case final f?) {
        _label(canvas, f(value), Offset(plot.right + 5, y));
      }
    }

    // Bars: one slot per day, with a small gap between them.
    final slot = plot.width / values.length;
    final barWidth = (slot * 0.7).clamp(1.0, 18.0);

    // The selected column is banded before the bars are drawn, so a day with
    // nothing logged still shows what was tapped.
    if (selected case final i?) {
      canvas.drawRect(
        Rect.fromLTWH(plot.left + slot * i, plot.top, slot, plot.height),
        Paint()..color = highlight.withValues(alpha: 0.14),
      );
    }

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
        Paint()..color = i == selected ? highlight : bar,
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
    // The tapped day is labelled whether or not it made the cut, so the axis
    // agrees with the caption.
    if (selected case final i? when i < labels.length) marks.add(i);

    for (final i in marks) {
      if (i >= labels.length) continue;
      _label(
        canvas,
        labels[i],
        Offset(plot.left + slot * (i + 0.5), plot.bottom + 4),
        centerX: true,
        emphasis: i == selected,
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
    bool emphasis = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: emphasis ? highlight : text,
          fontSize: 9,
          fontWeight: emphasis ? FontWeight.w700 : null,
        ),
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
      old.values != values ||
      old.selected != selected ||
      old.bar != bar ||
      old.format != format ||
      old.secondary != secondary;
}
