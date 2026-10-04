import 'package:flutter/material.dart';

/// One stretch of a [BandedTrack]: from [from] to [to] along it, 0 at the
/// left end and 1 at the right, in [colour].
typedef TrackBand = ({double from, double to, Color colour});

/// The three inks a warning goes through, for bands: the app's own colour,
/// then amber, then red.
///
/// Saturated rather than the card and chip tints, which a bar this thin
/// would lose against a background already that colour.
({Color ok, Color soon, Color overdue}) warningInks(BuildContext context) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  return (
    ok: theme.colorScheme.primary,
    soon: dark ? const Color(0xFFFFC94D) : const Color(0xFFD99A00),
    overdue: theme.colorScheme.error,
  );
}

/// A bar that empties from the right as time runs out, coloured by the
/// warning each stretch of it falls in.
///
/// Banded rather than one colour, so the bar shows what is coming as well as
/// what is left: as it empties the ordinary stretch goes first, and how much
/// is left before the amber is how long until the warning turns. A cut
/// between bands marks where one ends whether the bar has reached it yet or
/// not.
///
/// Used by the fridge's time-to-drink-by bar and Home's next-feed and
/// next-pump chips, so the two read the same way.
class BandedTrack extends StatelessWidget {
  const BandedTrack({
    super.key,
    required this.remaining,
    required this.bands,
    required this.height,
    this.cut,
    this.rounded = true,
  });

  /// How much is left, 1 to 0; the bar is filled from 0 to here.
  final double remaining;

  final List<TrackBand> bands;
  final double height;

  /// The colour of the cuts between bands: what the bar sits on. Defaults to
  /// the surface.
  final Color? cut;

  /// Rounded ends. Off where the bar runs along an edge whose own corners
  /// already shape it.
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = remaining.clamp(0.0, 1.0);
    final cuts = [
      for (final b in bands)
        if (b.to < 1) b.to,
    ];

    final bar = LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                key: const ValueKey('track'),
                color: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
            for (final (i, band) in bands.indexed)
              if (left > band.from)
                Positioned(
                  left: w * band.from,
                  top: 0,
                  bottom: 0,
                  width: w * ((left < band.to ? left : band.to) - band.from),
                  child: ColoredBox(
                    key: ValueKey('band-$i'),
                    color: band.colour,
                  ),
                ),
            for (final at in cuts)
              Positioned(
                left: w * at - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: ColoredBox(color: cut ?? scheme.surface),
              ),
          ],
        );
      },
    );

    return SizedBox(
      height: height,
      child: rounded
          ? ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: bar,
            )
          : bar,
    );
  }
}
