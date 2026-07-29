import 'package:flutter/material.dart';

import '../../core/format/unit_system.dart';
import '../feeding/feeding_format.dart';
import 'feed_clock_data.dart';

/// When feeds happen, day by day (KAN-185).
///
/// Days run down the chart and hours run across, one dot per feed. The daily
/// bar charts answer "how many"; this answers "when", which is the question
/// behind cluster feeding and the overnight gap.
///
/// One series, so no legend — the section title names it.
class FeedClockChart extends StatefulWidget {
  const FeedClockChart({super.key, required this.rows, required this.units});

  final List<FeedClockRow> rows;
  final UnitSystem units;

  @override
  State<FeedClockChart> createState() => _FeedClockChartState();
}

class _FeedClockChartState extends State<FeedClockChart> {
  FeedDot? _selected;

  /// Rows shrink for a month so the whole range still fits without scrolling,
  /// but never below the point where dots would collide vertically.
  double get _rowHeight => widget.rows.length > 10 ? 11 : 18;

  @override
  void didUpdateWidget(FeedClockChart old) {
    super.didUpdateWidget(old);
    // The selected dot belongs to the old range; keeping it would caption a
    // feed that is no longer plotted.
    if (old.rows != widget.rows) _selected = null;
  }

  void _handleTap(TapUpDetails details, Size size) {
    final geometry = _ClockGeometry(rows: widget.rows, rowHeight: _rowHeight);
    setState(() => _selected = geometry.dotAt(details.localPosition, size));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = widget.rows.length * _rowHeight + _ClockGeometry.chrome;
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, height);
              return GestureDetector(
                onTapUp: (d) => _handleTap(d, size),
                child: CustomPaint(
                  painter: _FeedClockPainter(
                    rows: widget.rows,
                    rowHeight: _rowHeight,
                    selected: selected,
                    dot: theme.colorScheme.primary,
                    grid: theme.colorScheme.outlineVariant,
                    text: theme.colorScheme.onSurfaceVariant,
                    // Ringing each dot in the surface colour keeps overlapping
                    // feeds countable instead of merging into a blob.
                    surface: theme.colorScheme.surface,
                    highlight: theme.colorScheme.tertiary,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        // The caption doubles as the tooltip: dots are too small to label, and
        // a tap target that reveals nothing is worse than none.
        Text(
          selected == null
              ? 'Tap a dot for details'
              : _describe(context, selected),
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

  String _describe(BuildContext context, FeedDot dot) {
    final at = TimeOfDay.fromDateTime(dot.event.startTime).format(context);
    final details = FeedingFormat.details(dot.event, widget.units);
    final label = FeedingFormat.typeLabel(dot.event.type);
    final head =
        '${dot.event.startTime.month}/${dot.event.startTime.day} · $at';
    return details.isEmpty ? '$head · $label' : '$head · $label · $details';
  }
}

/// Where dots land, shared by the painter and the tap handler so the two
/// can't disagree about what was hit.
class _ClockGeometry {
  const _ClockGeometry({required this.rows, required this.rowHeight});

  final List<FeedClockRow> rows;
  final double rowHeight;

  static const _leftPad = 34.0;
  static const _rightPad = 10.0;
  static const _topPad = 4.0;
  static const _bottomPad = 18.0;

  /// Vertical space the axes take, on top of the rows themselves.
  static const chrome = _topPad + _bottomPad;

  Rect plot(Size size) => Rect.fromLTRB(
    _leftPad,
    _topPad,
    size.width - _rightPad,
    size.height - _bottomPad,
  );

  Offset centre(Rect plot, FeedDot d) => Offset(
    plot.left + plot.width * d.dayFraction,
    plot.top + rowHeight * (d.dayIndex + 0.5),
  );

  /// The dot nearest [point], or null if the tap landed in open space.
  /// Named to avoid colliding with `CustomPainter.hitTest`.
  FeedDot? dotAt(Offset point, Size size) {
    final rect = plot(size);
    FeedDot? best;
    var bestDistance = double.infinity;
    for (final row in rows) {
      for (final d in row.dots) {
        final distance = (centre(rect, d) - point).distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = d;
        }
      }
    }
    // A generous radius: the dots are small, and fingers are not.
    return bestDistance <= 22 ? best : null;
  }
}

class _FeedClockPainter extends CustomPainter {
  _FeedClockPainter({
    required this.rows,
    required this.rowHeight,
    required this.selected,
    required this.dot,
    required this.grid,
    required this.text,
    required this.surface,
    required this.highlight,
  });

  final List<FeedClockRow> rows;
  final double rowHeight;
  final FeedDot? selected;
  final Color dot;
  final Color grid;
  final Color text;
  final Color surface;
  final Color highlight;

  _ClockGeometry get _geometry =>
      _ClockGeometry(rows: rows, rowHeight: rowHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _geometry;
    final plot = geometry.plot(size);

    // Hour gridlines every six hours, plus midnight at both edges.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    const marks = [0, 6, 12, 18, 24];
    const labels = ['12a', '6a', '12p', '6p', '12a'];
    for (var i = 0; i < marks.length; i++) {
      final x = plot.left + plot.width * (marks[i] / 24);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      _label(canvas, labels[i], Offset(x, plot.bottom + 9), centerX: true);
    }

    // Row labels: every row on a week, every third on a month, so the dates
    // stay readable as the rows compress.
    final labelStep = rowHeight < 14 ? 3 : 1;
    for (var i = 0; i < rows.length; i++) {
      if (i % labelStep != 0) continue;
      final y = plot.top + rowHeight * (i + 0.5);
      final d = rows[i].day;
      _label(
        canvas,
        '${d.month}/${d.day}',
        Offset(plot.left - 6, y),
        anchorRight: true,
      );
    }

    // Dots last, so they sit above the grid.
    final ringPaint = Paint()
      ..color = surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dotPaint = Paint()..color = dot;
    final radius = rowHeight < 14 ? 3.5 : 4.5;

    for (final row in rows) {
      for (final d in row.dots) {
        final centre = geometry.centre(plot, d);
        final isSelected = identical(d, selected);
        canvas.drawCircle(
          centre,
          isSelected ? radius + 2 : radius,
          isSelected ? (Paint()..color = highlight) : dotPaint,
        );
        canvas.drawCircle(centre, isSelected ? radius + 2 : radius, ringPaint);
      }
    }
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
  bool shouldRepaint(_FeedClockPainter old) =>
      old.rows != rows || old.selected != selected || old.dot != dot;
}
