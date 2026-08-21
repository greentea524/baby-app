import 'package:flutter/material.dart';

import '../../data/models/diaper_event.dart';
import '../timeline/timeline_format.dart';
import 'chart_palette.dart';
import 'day_view_data.dart';

/// The day's diapers as one bar split by what was in them, plus the answer to
/// the question the bar is really being asked: has there been a poo yet.
///
/// A stacked bar rather than a pie, on purpose. With four or five diapers a
/// day a pie is three wedges of noise — and, more to the point, a pie cannot
/// draw an absence. "No dirty one yet" is exactly the answer being looked
/// for, and in a pie it is a missing slice, indistinguishable from a chart
/// that has no data. Here the whole bar is the day and a missing segment is
/// visibly missing.
///
/// Built from ordinary widgets rather than a painter: it is three rectangles
/// and some text, so it scales with the reader's text size and announces
/// itself without any of the work a `CustomPaint` would need (#24).
class DiaperMixBar extends StatelessWidget {
  const DiaperMixBar({
    super.key,
    required this.mix,
    required this.lastWithPoop,
    required this.now,
  });

  final DiaperMix mix;

  /// The most recent diaper with something in it, from any day — null if
  /// there has never been one.
  final DiaperEvent? lastWithPoop;

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colours = DayColours.of(context);

    // "Both" is drawn as both colours rather than a third invented one, so
    // it is read off the other two instead of being remembered. It used to
    // be the dirty colour at 55% opacity, which is not a second colour.
    final segments = <({String label, int count, Color colour, Gradient? mix})>[
      (label: 'Wet', count: mix.wet, colour: colours.wet, mix: null),
      (label: 'Dirty', count: mix.dirty, colour: colours.diaper, mix: null),
      (label: 'Both', count: mix.both, colour: colours.wet, mix: colours.both),
    ];
    final present = segments.where((s) => s.count > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: _summary(),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 18,
                    child: present.isEmpty
                        ? ColoredBox(color: scheme.surfaceContainerHighest)
                        // Stretch, not the default centre: a ColoredBox with
                        // no child takes the smallest height its constraints
                        // allow, and a Row hands its children loose ones. The
                        // bar laid out at full width and zero height, which
                        // draws as nothing at all.
                        // Hairline gaps between segments. Without them the
                        // split "both" block butts its teal half against the
                        // dirty amber beside it, and a three-part bar reads
                        // as four.
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, s) in present.indexed) ...[
                                if (i > 0) const SizedBox(width: 2),
                                Expanded(
                                  flex: s.count,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: s.mix == null ? s.colour : null,
                                      gradient: s.mix,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                // A Wrap so the counts fold rather than overflow.
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final s in segments)
                      _Count(
                        label: s.label,
                        count: s.count,
                        colour: s.colour,
                        mix: s.mix,
                        muted: s.count == 0,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(_pooLine(), style: theme.textTheme.bodyMedium),
      ],
    );
  }

  /// "2 dirty today, last at 1:43 PM", or the honest version of "none yet".
  ///
  /// The elapsed time matters more than the count. "None yet today" is
  /// alarming at six in the morning and unremarkable at six in the evening;
  /// what separates the two is when the last one actually was.
  String _pooLine() {
    if (mix.withPoop > 0) {
      final n = mix.withPoop;
      return '$n dirty diaper${n == 1 ? '' : 's'} today.';
    }
    final last = lastWithPoop;
    if (last == null) return 'No dirty diaper logged yet.';
    return 'None yet today — the last was '
        '${TimelineFormat.interval(now.difference(last.time).inMinutes)} ago.';
  }

  String _summary() {
    if (mix.total == 0) return 'Diapers today. None logged.';
    return 'Diapers today. ${mix.total} in total, '
        '${mix.wet} wet, ${mix.dirty} dirty, ${mix.both} both.';
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.label,
    required this.count,
    required this.colour,
    required this.muted,
    this.mix,
  });

  final String label;
  final int count;
  final Color colour;

  /// Set for "both", whose swatch carries the same split as its segment.
  final Gradient? mix;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A zero is kept rather than hidden: the whole point is being able to see
    // that a kind has not happened today.
    final tone = muted ? theme.colorScheme.onSurfaceVariant : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: muted
                ? theme.colorScheme.surfaceContainerHighest
                : (mix == null ? colour : null),
            gradient: muted ? null : mix,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$count $label',
          style: theme.textTheme.bodySmall?.copyWith(color: tone),
        ),
      ],
    );
  }
}
