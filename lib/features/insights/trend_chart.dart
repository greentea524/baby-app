import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../common/chart_semantics.dart';
import '../common/chart_text.dart';

/// A compact bar chart of one metric across a date range (KAN-166).
///
/// Hand-painted for the same reason as the growth chart: it keeps the app
/// dependency-free and the bars are simple enough not to warrant a library.
///
/// Tap a bar to read its day and value. The bars are only a few pixels wide on
/// a month range and carry no labels of their own, so without this the chart
/// showed a shape you could not interrogate — the numbers behind it were only
/// available by exporting.
///
/// A screen reader gets the same numbers a different way (#24): the chart
/// announces a summary, and every bar is its own focusable node saying what
/// the caption would say if you could tap it.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.values,
    required this.labels,
    required this.title,
    this.subtitle,
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

  /// What the chart is of. Drawn by the section above; used here only to
  /// open the spoken summary, which otherwise would not say what it counts.
  final String title;
  final String? subtitle;

  final double height;

  /// Formats the value wherever it is shown. Defaults to a trimmed number.
  final String Function(double)? valueFormat;

  /// Formats the y-axis ticks alone, for when [valueFormat] is too wide for
  /// the gutter. A duration is the case in point: "13h 12m" crowds the axis,
  /// but shortening the tapped value to "13.2h" would throw away precision
  /// the caption has room for. Defaults to [valueFormat].
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

  void _handleTap(Offset at, Size size, TrendGeometry geometry) {
    setState(() => _selected = geometry.indexAt(at, size));
  }

  /// "Jul 4 · 240 ml (8.1 fl oz)" — what a bar is worth.
  String _describe(int i) {
    final format = widget.valueFormat ?? TrendChart.trim;
    final value = format(widget.values[i]);
    final second = widget.secondaryFormat;
    final suffix = second == null ? '' : ' (${second(widget.values[i])})';
    final label = i < widget.labels.length ? widget.labels[i] : 'Bar ${i + 1}';
    return '$label · $value$suffix';
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

    final axisFormat =
        widget.axisFormat ?? widget.valueFormat ?? TrendChart.trim;
    final labels = ChartText.of(
      context,
      style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
    );

    // The gutters are measured, not assumed: at a larger text size the tick
    // labels are wider, and a fixed 36px gutter would clip them. Measured
    // here rather than in the painter because the hit test needs the same
    // number, and the two agreeing is the whole point of TrendGeometry.
    final scale = TrendScale.of(widget.values);
    final geometry = TrendGeometry.measured(
      count: widget.values.length,
      labels: labels,
      axisLabels: [for (final t in scale.ticks) axisFormat(t)],
      secondaryLabels: widget.secondaryFormat == null
          ? null
          : [for (final t in scale.ticks) widget.secondaryFormat!(t)],
    );

    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, widget.height);
              return Semantics(
                label: barChartSummary(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  values: widget.values,
                  labels: widget.labels,
                  format: widget.valueFormat ?? TrendChart.trim,
                ),
                // The per-bar nodes below are the detail; this is the
                // overview. Without explicitChildNodes the two would be
                // flattened into one unreadable announcement.
                explicitChildNodes: true,
                child: GestureDetector(
                  onTapUp: (d) => _handleTap(d.localPosition, size, geometry),
                  child: CustomPaint(
                    painter: _TrendChartPainter(
                      values: widget.values,
                      labels: widget.labels,
                      selected: selected,
                      geometry: geometry,
                      scale: scale,
                      bar: theme.colorScheme.primary,
                      highlight: theme.colorScheme.tertiary,
                      grid: theme.colorScheme.outlineVariant,
                      text: labels,
                      format: axisFormat,
                      secondary: widget.secondaryFormat,
                      describe: _describe,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // The caption doubles as the tooltip: the bars are too narrow to label
        // individually, and a tap target that reveals nothing is worse than
        // none. Unlike the axis, this is a real Text and scales all the way.
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

/// The vertical scale: where the top of the chart sits and what the
/// gridlines are worth.
///
/// Hoisted out of the painter because the gutter has to be measured from the
/// tick labels before there is a painter to ask.
class TrendScale {
  const TrendScale(this.top, {this.tickCount = 3});

  /// Rounds the top of the scale up so gridlines land on tidy numbers.
  factory TrendScale.of(List<double> values) {
    if (values.isEmpty) return const TrendScale(1);
    final max = values.reduce((a, b) => a > b ? a : b);
    return TrendScale(max <= 0 ? 1.0 : max * 1.1);
  }

  final double top;
  final int tickCount;

  List<double> get ticks => [
    for (var i = 0; i <= tickCount; i++) top * i / tickCount,
  ];
}

/// Where the plot sits inside the chart, shared by the painter and the hit
/// test so a tap lands on the bar it looks like it landed on.
class TrendGeometry {
  const TrendGeometry({
    required this.count,
    required this.leftPad,
    required this.rightPad,
    required this.bottomPad,
    this.topPad = 10.0,
  });

  /// Sizes the gutters to the labels that will go in them.
  ///
  /// The padding used to be constants — 36px on the left — which was fine
  /// until the axis labels started following the reader's text size (#24).
  /// Both the painter and the hit test take the geometry from here, so
  /// neither can be working from a stale idea of where the plot begins.
  factory TrendGeometry.measured({
    required int count,
    required ChartText labels,
    required List<String> axisLabels,
    List<String>? secondaryLabels,
  }) => TrendGeometry(
    count: count,
    leftPad: labels.widest(axisLabels) + 9,
    rightPad: secondaryLabels == null ? 8 : labels.widest(secondaryLabels) + 9,
    bottomPad: labels.lineHeight + 10,
  );

  final int count;

  /// Measured from the widest tick label rather than fixed, so the axis has
  /// room at whatever text size the reader is running (#24).
  final double leftPad;
  final double rightPad;
  final double bottomPad;
  final double topPad;

  Rect plot(Size size) => Rect.fromLTRB(
    leftPad,
    topPad,
    size.width - rightPad,
    size.height - bottomPad,
  );

  /// The horizontal slice belonging to day [i].
  Rect column(Size size, int i) {
    final rect = plot(size);
    final slot = rect.width / count;
    return Rect.fromLTWH(rect.left + slot * i, rect.top, slot, rect.height);
  }

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
    required this.geometry,
    required this.scale,
    required this.bar,
    required this.highlight,
    required this.grid,
    required this.text,
    required this.format,
    required this.describe,
    this.secondary,
  });

  final List<double> values;
  final List<String> labels;
  final int? selected;
  final TrendGeometry geometry;
  final TrendScale scale;
  final Color bar;
  final Color highlight;
  final Color grid;
  final ChartText text;
  final String Function(double) format;
  final String Function(int) describe;
  final String Function(double)? secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = geometry.plot(size);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final ticks = scale.ticks;
    for (var i = 0; i < ticks.length; i++) {
      final y = plot.bottom - plot.height * i / scale.tickCount;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      text.paint(
        canvas,
        format(ticks[i]),
        Offset(plot.left - 5, y),
        anchorRight: true,
      );
      if (secondary case final f?) {
        text.paint(canvas, f(ticks[i]), Offset(plot.right + 5, y));
      }
    }

    // Bars: one slot per day, with a small gap between them.
    final slot = plot.width / values.length;
    final barWidth = (slot * 0.7).clamp(1.0, 18.0);

    // The selected column is banded before the bars are drawn, so a day with
    // nothing logged still shows what was tapped.
    if (selected case final i?) {
      canvas.drawRect(
        geometry.column(size, i),
        Paint()..color = highlight.withValues(alpha: 0.14),
      );
    }

    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final h = plot.height * (values[i] / scale.top);
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
    // and the widest one is what decides the spacing. At a larger text size
    // fewer fit, which is the behaviour that keeps them from overlapping.
    if (labels.isEmpty) return;
    final widest = text.widest(labels);
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
      text.paint(
        canvas,
        labels[i],
        Offset(plot.left + slot * (i + 0.5), plot.bottom + 4),
        centerX: true,
        override: i == selected
            ? text.style.copyWith(color: highlight, fontWeight: FontWeight.w700)
            : null,
      );
    }
  }

  /// One node per bar, each saying what tapping it would say.
  ///
  /// The rects are the tap columns, so what a reader focuses is exactly what
  /// a finger would hit — the two cannot drift apart because both come from
  /// [TrendGeometry].
  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (var i = 0; i < values.length; i++)
          CustomPainterSemantics(
            rect: geometry.column(size, i),
            properties: SemanticsProperties(
              label: describe(i),
              selected: i == selected,
              button: true,
              textDirection: TextDirection.ltr,
            ),
          ),
      ];

  @override
  bool shouldRepaint(_TrendChartPainter old) =>
      old.values != values ||
      old.selected != selected ||
      old.bar != bar ||
      old.text != text ||
      old.format != format ||
      old.secondary != secondary;

  @override
  bool shouldRebuildSemantics(_TrendChartPainter old) =>
      old.values != values || old.selected != selected || old.labels != labels;
}
