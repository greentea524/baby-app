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

  static String labelOf(DayMarkKind kind) => switch (kind) {
    DayMarkKind.feed => 'Feeds',
    DayMarkKind.snack => 'Top-ups',
    DayMarkKind.diaper => 'Diapers',
    DayMarkKind.pump => 'Pumping',
  };

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
        _Legend(kinds: _kindsPresent(), colourOf: colourOf),
      ],
    );
  }

  List<DayMarkKind> _kindsPresent() => [
    for (final kind in DayMarkKind.values)
      if (marks.any((m) => m.kind == kind)) kind,
  ];

  /// Spoken as a sentence, because a band of ticks is nothing at all to a
  /// screen reader (#24).
  String _summary() {
    final counts = <DayMarkKind, int>{};
    for (final m in marks) {
      counts[m.kind] = (counts[m.kind] ?? 0) + 1;
    }
    final parts = [
      for (final entry in counts.entries)
        '${entry.value} ${labelOf(entry.key).toLowerCase()}',
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
  const _Legend({required this.kinds, required this.colourOf});

  final List<DayMarkKind> kinds;
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
        for (final kind in kinds)
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
                  color: _hollow(kind) ? null : colourOf(kind),
                  border: _hollow(kind)
                      ? Border.all(color: colourOf(kind), width: 1.6)
                      : null,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                DayTimelineStrip.labelOf(kind),
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
                '${DayTimelineStrip.labelOf(mark.kind)} at '
                '${DayTimelineStrip._clock(mark.hour)}',
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRebuildSemantics(_StripPainter old) => old.marks != marks;
}
