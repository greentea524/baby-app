import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_bottle.dart';
import '../feeding/feeding_format.dart';
import 'bottle_gauge.dart';
import 'fridge_order.dart';

/// What a mixed bottle holds, oldest first: a swatch in its band's shade,
/// and how much of what age — "● 60 ml 2d  ● 40 ml 5h".
///
/// [dense] for the card, where it takes the one line a note would and is
/// scaled down to fit it; otherwise a line for each, with the time.
class MixKey extends ConsumerWidget {
  const MixKey({
    super.key,
    required this.bottle,
    required this.now,
    this.dense = false,
  });

  final FridgeBottle bottle;
  final DateTime now;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final units = ref.watch(unitSystemProvider);
    final layers = bottle.layers;
    final shades = mixShades(scheme, bottle.kind, layers.length);
    final style =
        (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: scheme.onSurfaceVariant);

    Widget swatch(Color c) => Container(
      width: dense ? 10 : 14,
      height: dense ? 10 : 14,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outline, width: 0.8),
      ),
    );

    if (dense) {
      return Semantics(
        label:
            'Mixed: ${[for (final p in layers) '${formatVolume(p.amountMl, units)} from ${hoursAgo(p.filledAt, now)}'].join(', ')}',
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, p) in layers.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                swatch(shades[i]),
                const SizedBox(width: 3),
                Text(
                  '${formatMl(p.amountMl)} · ${shortAge(p.filledAt, now)}',
                  style: style,
                  maxLines: 1,
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, p) in layers.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                swatch(shades[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${formatVolume(p.amountMl, units)} · '
                    '${bottle.kind.filledLabel.toLowerCase()} '
                    '${FeedingFormat.clockStamp(context, p.filledAt, now: now)}'
                    ' · ${hoursAgo(p.filledAt, now)}',
                    style: style,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
