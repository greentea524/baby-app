import 'package:flutter/material.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/milk_kind.dart';
import 'chart_palette.dart';
import 'milk_mix.dart';

/// The kinds a milk chart draws, in the order it draws them. Unrecorded milk
/// last, so the kinds that are known sit together from the left.
const List<MilkKind?> milkOrder = [...MilkKind.values, null];

/// What a bottle of [kind] is called on a chart.
String milkLabel(MilkKind? kind) => kind?.label ?? 'Not recorded';

/// "80%": a share, rounded, with anything real but tiny kept off zero.
String _percent(double share) {
  if (share <= 0) return '0%';
  final pct = (share * 100).round();
  return pct == 0 ? '<1%' : '$pct%';
}

/// Bottle milk as one bar split by kind, plus the share that answers the
/// question the chart is for: how much of it was breast milk.
///
/// A single stacked bar rather than a pie, as with the diapers: there are
/// rarely more than two kinds in a day, and the whole bar standing for every
/// bottle makes a small share of formula visibly small. Every segment is
/// named with its amount and share underneath, so no reading depends on
/// telling the colours apart.
class MilkMixBar extends StatelessWidget {
  const MilkMixBar({super.key, required this.mix, required this.units});

  final MilkMix mix;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colours = DayColours.of(context);
    final present = [
      for (final k in milkOrder)
        if (mix.ml(k) > 0) k,
    ];

    return Semantics(
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
                    // Stretch, and a 2pt gap between segments, for the
                    // reasons the diaper bar gives.
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, k) in present.indexed) ...[
                            if (i > 0) const SizedBox(width: 2),
                            Expanded(
                              // Tenths of a millilitre, so a 2 ml top-up of
                              // formula still gets a sliver.
                              flex: (mix.ml(k) * 10).round().clamp(1, 1 << 30),
                              child: ColoredBox(color: colours.milk(k, scheme)),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final k in present)
                  _Key(
                    colour: colours.milk(k, scheme),
                    text:
                        '${milkLabel(k)} ${formatVolume(mix.ml(k), units)} · '
                        '${_percent(mix.share(k))}',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(headline(mix), style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  /// The sentence under the bar: the breast milk share, said plainly.
  ///
  /// Measured against the bottles whose milk is known. Counting unrecorded
  /// ones in the total would read an old week of breast milk as mostly
  /// "something else"; leaving them out of the total says only what is known.
  static String headline(MilkMix mix) {
    final known = mix.totalMl - mix.unknownMl;
    if (known <= 0) return 'Milk type was not recorded for these bottles.';
    final share = mix.breastMilkMl / known;
    final note = mix.unknownMl > 0
        ? ' (of bottles with a milk type recorded)'
        : '';
    if (share >= 1) return 'All breast milk$note.';
    if (share <= 0) return 'No breast milk in bottles$note.';
    return 'Breast milk was ${_percent(share)} of bottles$note.';
  }

  String _summary() {
    if (mix.totalMl <= 0) return 'Bottles by milk. None logged.';
    final parts = [
      for (final k in milkOrder)
        if (mix.ml(k) > 0)
          '${milkLabel(k)} ${formatVolume(mix.ml(k), units)}, '
              '${_percent(mix.share(k))}',
    ];
    return 'Bottles by milk. ${parts.join('; ')}. ${headline(mix)}';
  }
}

/// Pumped against breast milk fed, as two bars on one scale.
///
/// Both are millilitres of the same milk, so they share an axis honestly:
/// the longer bar sets the scale and the shorter one is read against it.
/// The percentage is written out underneath, because "is pumping keeping up"
/// is a number, and the bars are there to show it at a glance.
class PumpedVsFed extends StatelessWidget {
  const PumpedVsFed({
    super.key,
    required this.pumpedMl,
    required this.mix,
    required this.units,
  });

  final double pumpedMl;
  final MilkMix mix;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = DayColours.of(context);
    final fedMl = mix.breastMilkMl;
    final top = pumpedMl > fedMl ? pumpedMl : fedMl;

    Widget row(String label, double ml, Color colour) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · ${formatVolume(ml, units)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: top <= 0 ? 0 : (ml / top).clamp(0.0, 1.0),
                    child: ColoredBox(color: colour),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label:
          'Pumped ${formatVolume(pumpedMl, units)}. Breast milk fed from '
          'bottles ${formatVolume(fedMl, units)}. ${headline(pumpedMl, mix)}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Pumped', pumpedMl, colours.pump),
            row('Fed as breast milk', fedMl, colours.feed),
            const SizedBox(height: 2),
            Text(headline(pumpedMl, mix), style: theme.textTheme.bodyMedium),
            if (mix.unknownMl > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Bottles logged before milk type was recorded are not '
                'counted as breast milk.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Pumped 110% of the breast milk fed", and which way the difference went.
  static String headline(double pumpedMl, MilkMix mix) {
    final coverage = mix.pumpCoverage(pumpedMl);
    if (coverage == null) {
      return pumpedMl > 0
          ? 'No breast milk fed from bottles.'
          : 'Nothing pumped or fed as breast milk.';
    }
    final pct = _percent(coverage);
    if (coverage >= 1) {
      return 'Pumped $pct of the breast milk fed.';
    }
    return 'Pumped $pct of the breast milk fed — the rest came from milk '
        'pumped earlier.';
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.colour, required this.text});

  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        // Text ink, not the series colour: the swatch carries identity.
        Flexible(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
