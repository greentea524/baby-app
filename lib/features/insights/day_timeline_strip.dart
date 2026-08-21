import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../common/chart_text.dart';
import 'chart_palette.dart';
import 'day_view_data.dart';
import 'feed_pattern_data.dart';

/// The day as a 24-hour band, one tick per event (#—).
///
/// The chart the day view is really for. A bar chart answers "how many",
/// which for a single day is a number and does not need a chart; this
/// answers "when", and with it how clustered the feeds were, how long the
/// night gap ran, and how long it has been since anything happened.
///
/// Night is shaded rather than drawn as a boundary, so the gap a caregiver
/// cares about is a shape rather than something to work out from tick marks.
class DayTimelineStrip extends StatelessWidget {
  const DayTimelineStrip({super.key, required this.marks, this.height = 92});

  final List<DayMark> marks;
  final double height;

  /// Which row of the band a kind sits on, so overlapping events at the same
  /// hour do not land on top of each other.
  static int laneOf(DayMarkKind kind) => switch (kind) {
    DayMarkKind.feed || DayMarkKind.snack => 0,
    DayMarkKind.diaper => 1,
    DayMarkKind.pump => 2,
  };

  /// The name of one of them — what a single mark is.
  static String singularOf(DayMarkKind kind) => switch (kind) {
    DayMarkKind.feed => 'Feed',
    DayMarkKind.snack => 'Top-up',
    DayMarkKind.diaper => 'Diaper',
    DayMarkKind.pump => 'Pump',
  };

  /// "3 feeds", "1 top-up" — the legend's text, and the summary's.
  ///
  /// The count lives here rather than in a row above the chart: a legend
  /// that says what a colour means and how many there were of it answers
  /// both questions in the space one of them was using.
  static String countLabel(DayMarkKind kind, int count) {
    final name = singularOf(kind).toLowerCase();
    return '$count ${count == 1 ? name : '${name}s'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colours = DayColours.of(context);

    // A top-up shares the feed's colour because it *is* a feed; it is told
    // apart by being drawn hollow, not by a fainter shade of the same thing.
    Color colourOf(DayMarkKind kind) => switch (kind) {
      DayMarkKind.feed || DayMarkKind.snack => colours.feed,
      DayMarkKind.diaper => colours.diaper,
      DayMarkKind.pump => colours.pump,
    };

    if (marks.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Nothing logged on this day.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: _summary(),
          child: SizedBox(
            height: height,
            child: CustomPaint(
              painter: _StripPainter(
                marks: marks,
                colourOf: colourOf,
                night: scheme.onSurface.withValues(alpha: 0.05),
                grid: scheme.outlineVariant,
                text: ChartText.of(
                  context,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Legend(counts: _counts(), colourOf: colourOf),
      ],
    );
  }

  /// How many of each kind there were, in a fixed order, skipping kinds the
  /// day has none of — a key for something that is not on the chart is a
  /// line to read and nothing to find.
  Map<DayMarkKind, int> _counts() {
    final counts = <DayMarkKind, int>{};
    for (final kind in DayMarkKind.values) {
      final n = marks.where((m) => m.kind == kind).length;
      if (n > 0) counts[kind] = n;
    }
    return counts;
  }

  /// Spoken as a sentence, because a band of ticks is nothing at all to a
  /// screen reader (#24).
  String _summary() {
    final parts = [
      for (final entry in _counts().entries) countLabel(entry.key, entry.value),
    ];
    final first = _clock(marks.first.hour);
    final last = _clock(marks.last.hour);
    return 'The day as a timeline. ${parts.join(', ')}, '
        'from $first to $last.';
  }

  static String _clock(double hour) {
    final h = hour.floor();
    final m = ((hour - h) * 60).round();
    return '${hourLabel(h)}${m == 0 ? '' : ' $m'}';
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.counts, required this.colourOf});

  final Map<DayMarkKind, int> counts;
  final Color Function(DayMarkKind) colourOf;

  static bool _hollow(DayMarkKind kind) => kind == DayMarkKind.snack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A Wrap so it folds rather than overflows at a large text size.
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final entry in counts.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The key matches the mark: a hollow swatch for the hollow
              // tick, so the legend explains the drawing rather than
              // restating its colour.
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _hollow(entry.key) ? null : colourOf(entry.key),
                  border: _hollow(entry.key)
                      ? Border.all(color: colourOf(entry.key), width: 1.6)
                      : null,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                DayTimelineStrip.countLabel(entry.key, entry.value),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
      ],
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.marks,
    required this.colourOf,
    required this.night,
    required this.grid,
    required this.text,
  });

  final List<DayMark> marks;
  final Color Function(DayMarkKind) colourOf;
  final Color night;
  final Color grid;
  final ChartText text;

  static const _lanes = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final labelHeight = text.lineHeight + 6;
    final band = Rect.fromLTRB(0, 0, size.width, size.height - labelHeight);
    double x(double hour) => band.left + band.width * (hour / 24);

    // Night, shaded in two pieces because it wraps midnight.
    final nightPaint = Paint()..color = night;
    canvas.drawRect(
      Rect.fromLTRB(x(0), band.top, x(nightEndHour.toDouble()), band.bottom),
      nightPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(x(nightStartHour.toDouble()), band.top, x(24), band.bottom),
      nightPaint,
    );

    // Hour rules every six hours, which is as many as a phone can label.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h += 6) {
      final dx = x(h.toDouble());
      canvas.drawLine(Offset(dx, band.top), Offset(dx, band.bottom), gridPaint);
      if (h == 24) continue;
      text.paint(
        canvas,
        hourLabel(h),
        Offset(dx + 3, band.bottom + labelHeight / 2),
      );
    }

    // A lane per kind, so two things at the same minute stay legible.
    final laneHeight = band.height / _lanes;
    for (final mark in marks) {
      final lane = DayTimelineStrip.laneOf(mark.kind);
      final top = band.top + laneHeight * lane + 4;
      final hollow = mark.kind == DayMarkKind.snack;
      // Top-ups share the feed lane and the feed colour, so they are told
      // apart by being drawn as an outline — a cue that survives being
      // printed, dimmed, or read by someone who cannot separate the hues.
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x(mark.hour) - (hollow ? 2.5 : 1.5),
          top,
          hollow ? 5 : 3,
          laneHeight - 8,
        ),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = colourOf(mark.kind)
          ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.marks != marks || old.night != night || old.text != text;

  /// One node per event: a band of ticks is unreachable otherwise, and the
  /// time each one happened is the whole content of this chart.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final labelHeight = text.lineHeight + 6;
    final band = Rect.fromLTRB(0, 0, size.width, size.height - labelHeight);
    return [
      for (final mark in marks)
        CustomPainterSemantics(
          rect: Rect.fromCenter(
            center: Offset(
              band.width * (mark.hour / 24),
              band.top + band.height * 0.5,
            ),
            width: 24,
            height: band.height,
          ),
          properties: SemanticsProperties(
            label:
                '${DayTimelineStrip.singularOf(mark.kind)} at '
                '${DayTimelineStrip._clock(mark.hour)}',
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRebuildSemantics(_StripPainter old) => old.marks != marks;
}
