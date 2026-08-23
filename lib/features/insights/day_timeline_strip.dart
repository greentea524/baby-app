import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../common/chart_text.dart';
import 'chart_palette.dart';
import 'day_view_data.dart';
import 'feed_pattern_data.dart';

/// The day as a 24-hour band, one dot per event (#26).
///
/// The chart the day view is really for. A bar chart answers "how many",
/// which for a single day is a number and does not need a chart; this
/// answers "when", and with it how clustered the feeds were, how long the
/// night gap ran, and how long it has been since anything happened.
///
/// Night is shaded rather than drawn as a boundary, so the gap a caregiver
/// cares about is a shape rather than something to work out from marks.
///
/// Everything sits on one row. It used to be three lanes of thin ticks, one
/// per kind, which answered the question per-kind and left the whole-day
/// rhythm to be assembled by eye across rows — and cost the ~50pt of height
/// the lanes needed to be visible at all.
///
/// A single row only works because the marks are dots with a ring in the
/// surface colour. On a phone the band is roughly 14pt an hour, so a feed and
/// a change ten minutes apart land on top of each other, and a feed hidden
/// behind a diaper is a wrong reading rather than an ugly one. The ring cuts a
/// visible crescent out of whatever it overlaps, so near-simultaneous events
/// read as two things close together — which is the truth. A 3pt tick had
/// nowhere to put a ring.
class DayTimelineStrip extends StatelessWidget {
  const DayTimelineStrip({super.key, required this.marks, this.height = 46});

  /// In time order, as [dayMarks] returns them — the strip nudges marks that
  /// would overlap, which needs to happen left to right.
  final List<DayMark> marks;

  final double height;

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
      // Otherwise the strip swells to whatever loose height it is handed —
      // it reads as 46pt plus a legend and measured 600 inside a Center.
      mainAxisSize: MainAxisSize.min,
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
                ring: scheme.surface,
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
              // The key matches the mark: a round swatch, hollow for the
              // hollow dot, so the legend explains the drawing rather than
              // restating its colour.
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _hollow(entry.key) ? null : colourOf(entry.key),
                  border: _hollow(entry.key)
                      ? Border.all(color: colourOf(entry.key), width: 2)
                      : null,
                  shape: BoxShape.circle,
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
    required this.ring,
    required this.text,
  });

  final List<DayMark> marks;
  final Color Function(DayMarkKind) colourOf;
  final Color night;
  final Color grid;

  /// The surface behind the band, used to halo each dot.
  final Color ring;

  final ChartText text;

  /// Small on purpose. The band is roughly 14pt an hour on a phone, so an 8pt
  /// dot already spans about 35 minutes where a 3pt tick spanned 13. On a
  /// chart whose whole content is *when*, a friendlier, rounder, bigger dot
  /// is the move that turns a timeline into a decoration.
  static const _dotRadius = 4.0;
  static const _ringWidth = 1.5;

  /// The outline that tells a top-up from a feed.
  static const _hollowStroke = 2.0;

  /// The closest two dots may be drawn before the later one is pushed right.
  ///
  /// The ring separates overlapping dots by cutting a crescent out of the one
  /// behind, and what is left of that one is exactly `gap - _ringWidth` wide.
  /// So the ring alone stops working at very small gaps: measured on a 340pt
  /// band, which is about 14pt an hour, two events ten minutes apart leave
  /// 0.8pt of the earlier dot — nothing, once antialiased. A feed and a nappy
  /// change logged together is the commonest case there is, and a feed hidden
  /// behind a diaper is a wrong reading rather than an ugly one.
  ///
  /// Two points of visible dot is enough to read, so that is the gap: the
  /// ring, plus two. It shifts a mark by at most a quarter hour at the
  /// density that triggers it, which is the cost of not losing it entirely.
  /// Positions inside a cluster are approximate; the times in the semantics
  /// labels are not.
  static const _minGap = _ringWidth + 2;

  @override
  void paint(Canvas canvas, Size size) {
    final labelHeight = text.lineHeight + 6;
    final band = Rect.fromLTRB(0, 0, size.width, size.height - labelHeight);

    // Shrinks rather than clipping when the hour labels grow at a large text
    // size and leave the band with less than a dot's worth of height.
    final radius = math.min(_dotRadius, (band.height - _ringWidth * 2) / 2);
    if (radius <= 0) return;

    // A dot at midnight or at midnight-tomorrow is centred on the edge and
    // loses its outer half, so the scale is inset by one — which costs a
    // little time accuracy at both ends and is worth it.
    final pad = radius + _ringWidth;
    final left = band.left + pad;
    final span = band.width - pad * 2;
    double x(double hour) => left + span * (hour / 24);

    // Night, shaded in two pieces because it wraps midnight. Taken out to the
    // band's own edges rather than the inset scale, so the padding does not
    // show as an unshaded sliver at either end.
    final nightPaint = Paint()..color = night;
    canvas.drawRect(
      Rect.fromLTRB(
        band.left,
        band.top,
        x(nightEndHour.toDouble()),
        band.bottom,
      ),
      nightPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        x(nightStartHour.toDouble()),
        band.top,
        band.right,
        band.bottom,
      ),
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

    // One row. Each dot lays its own ring down first, so the ring of a later
    // mark cuts into whatever it overlaps — that crescent is what keeps two
    // events minutes apart reading as two events.
    final centreY = band.top + band.height / 2;
    final ringPaint = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringWidth;

    // Relies on [marks] being in time order, which is what dayMarks returns.
    double? previous;
    for (final mark in marks) {
      var cx = x(mark.hour);
      if (previous != null && cx - previous < _minGap) {
        // Never past the end of the band: at the very end of the day there is
        // nowhere left to push, and piling up there beats drawing outside.
        cx = math.min(previous + _minGap, band.right - pad);
      }
      previous = cx;

      final centre = Offset(cx, centreY);
      canvas.drawCircle(centre, radius + _ringWidth / 2, ringPaint);

      // Top-ups share the feed colour because they *are* feeds, and are told
      // apart by being drawn as an outline — a cue that survives being
      // printed, dimmed, or read by someone who cannot separate the hues.
      final hollow = mark.kind == DayMarkKind.snack;
      final stroke = math.min(_hollowStroke, radius);
      canvas.drawCircle(
        centre,
        hollow ? radius - stroke / 2 : radius,
        Paint()
          ..color = colourOf(mark.kind)
          ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.marks != marks ||
      old.night != night ||
      old.ring != ring ||
      old.text != text;

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
