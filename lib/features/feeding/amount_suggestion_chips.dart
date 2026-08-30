import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/volume_entry.dart';
import '../pumping/pumping_format.dart';
import 'amount_suggestion_providers.dart';
import 'amount_suggestions.dart';

/// One-tap amounts under the bottle form's volume field (#31).
///
/// Chips rather than a segmented button: these are shortcuts that fill the
/// field, not a choice between three allowed volumes. The field stays where
/// the answer is typed, and an unusual feed needs no detour around them.
///
/// Renders nothing at all when there is nothing to suggest. A household on
/// its first day has no pattern, and inventing a ladder for them would say
/// the app knows something about their baby that it does not.
class AmountSuggestionChips extends ConsumerWidget {
  const AmountSuggestionChips({
    super.key,
    required this.unit,
    required this.onPick,
  });

  /// The unit the field is currently showing, so the chips read the same way
  /// the number will once it lands in the field.
  final VolumeUnit unit;

  /// Called with the chip's exact millilitres — never with its label, which
  /// in fluid ounces has already been rounded for display.
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(bottleAmountSuggestionsProvider);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final s in suggestions)
            ActionChip(
              // The pump chip is marked, because where it came from changes
              // what it means: the others are habit, this one is the milk
              // actually standing in the fridge.
              avatar: s.source == AmountSource.pump
                  ? Icon(PumpingFormat.icon, size: 18)
                  : null,
              tooltip: s.source == AmountSource.pump ? 'Your last pump' : null,
              label: Text('${unit.fieldText(s.millilitres)} ${unit.label}'),
              onPressed: () => onPick(s.millilitres),
            ),
        ],
      ),
    );
  }
}
