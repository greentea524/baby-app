import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../common/chart_text.dart';
import 'chart_palette.dart';
import 'day_view_data.dart';
import 'feed_pattern_data.dart';

/// The day as a 24-hour band, one line per event (#26).
///
/// The chart the day view is really for. A bar chart answers "how many",
/// which for a single day is a number and does not need a chart; this
/// answers "when", and with it how clustered the feeds were, how long the
/// night gap ran, and how long it has been since anything happened.
///
/// Night is shaded rather than drawn as a boundary, so the gap a caregiver
/// cares about is a shape rather than something to work out from marks.
///
/// Everything sits on one row. It used to be three lanes, one per kind, which
/// answered the question per-kind and left the whole-day rhythm to be
/// assembled by eye across rows — and cost the ~50pt of height the lanes
/// needed to be visible at all.
///
/// A single row only works because each mark carries a margin in the surface
/// colour. On a phone the band is roughly 14pt an hour, so a feed and a change
/// ten minutes apart land on top of each other, and a feed hidden behind a
/// diaper is a wrong reading rather than an ugly one. The halo of a later mark
/// cuts into whatever it overlaps, so near-simultaneous events read as two
/// things close together — which is the truth.
///
/// The marks were briefly dots. Two reasons they are lines instead. A line is
/// narrow, so it points at about 13 minutes where an 8pt dot pointed at 35 —
/// and this chart is nothing but *when*. And what survives an overlap is the
/// same width either way (`gap - halo`), but on a dot that remnant is the
/// tapering tip of a crescent, which reads as a chipped dot rather than as two
/// events; on a line it is a full-height sliver. A line also says honestly
/// that there is no second dimension here: every mark sits at the same height,
/// and a dot invites the eye to look for a meaning in that.
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
                halo: scheme.surface,
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

  static bool _short(DayMarkKind kind) => kind == DayMarkKind.snack;

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
              // The key matches the mark: a bar, run short for the short
              // one, so the legend explains the drawing rather than
              // restating its colour.
              SizedBox(
                width: 3,
                height: 12,
                child: Center(
                  child: ColoredBox(
                    color: colourOf(entry.key),
                    child: SizedBox(
                      width: 3,
                      height: _short(entry.key) ? 6 : 12,
                    ),
                  ),
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
    required this.halo,
    required this.text,
  });

  final List<DayMark> marks;
  final Color Function(DayMarkKind) colourOf;
  final Color night;
  final Color grid;

  /// The surface behind the band, used to halo each mark.
  final Color halo;

  final ChartText text;

  /// Half the width of a mark. Narrow on purpose: the band is roughly 14pt an
  /// hour on a phone, so a 3pt line spans about 13 minutes. This is a chart
  /// whose whole content is *when*, and every point of width is time the mark
  /// no longer points at.
  static const _halfWidth = 1.5;

  /// The surface-coloured margin drawn around each mark, so one that overlaps
  /// another still reads as two.
  static const _haloWidth = 1.5;

  /// A top-up is a feed, so it takes the feed's colour and is told apart by
  /// running short — a cue that survives being printed, dimmed, or read by
  /// someone who cannot separate the hues.
  static const _snackHeight = 0.45;

  /// The closest two marks may be drawn before the later one is pushed right.
  ///
  /// The halo separates overlapping marks by cutting into the one behind, and
  /// what is left of that one is exactly `gap - _haloWidth` wide. So the halo
  /// alone stops working at very small gaps: on a 340pt band, about 14pt an
  /// hour, two events ten minutes apart leave 0.8pt of the earlier mark —
  /// nothing, once antialiased. A feed and a nappy change logged together is
  /// the commonest case there is, and a feed hidden behind a diaper is a
  /// wrong reading rather than an ugly one.
  ///
  /// Two points of visible mark is enough to read, so that is the gap: the
  /// halo, plus two. Positions inside a cluster are therefore approximate;
  /// the times in the semantics labels are not.
  ///
  /// Lines need this less often than the dots they replaced. Marks only
  /// collide from `_halfWidth + _haloWidth` apart rather than a dot radius
  /// plus its ring, so the nudge fires at about 20 minutes rather than 40 —
  /// and what survives an overlap is a full-height sliver rather than the
  /// tapering tip of a crescent, which is the reason for the change.
  static const _minGap = _haloWidth + 2;

  @override
  void paint(Canvas canvas, Size size) {
    final labelHeight = text.lineHeight + 6;
    final band = Rect.fromLTRB(0, 0, size.width, size.height - labelHeight);

    if (band.height <= 0) return;

    // A mark at midnight or at midnight-tomorrow is centred on the edge and
    // loses its outer half, so the scale is inset by one — which costs a
    // little time accuracy at both ends and is worth it.
    const pad = _halfWidth + _haloWidth;
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

    // One row. Each mark lays its own halo down first, so the halo of a later
    // mark cuts into whatever it overlaps — that gap is what keeps two events
    // minutes apart reading as two events.
    final haloPaint = Paint()..color = halo;

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

      final height = mark.kind == DayMarkKind.snack
          ? band.height * _snackHeight
          : band.height;
      final top = band.top + (band.height - height) / 2;

      canvas.drawRect(
        Rect.fromLTWH(
          cx - _halfWidth - _haloWidth,
          top,
          (_halfWidth + _haloWidth) * 2,
          height,
        ),
        haloPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(cx - _halfWidth, top, _halfWidth * 2, height),
        Paint()..color = colourOf(mark.kind),
      );
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.marks != marks ||
      old.night != night ||
      old.halo != halo ||
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
