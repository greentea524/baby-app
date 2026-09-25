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

  /// Called with the chip tapped: its exact millilitres — never its label,
  /// which in fluid ounces has already been rounded for display — and where
  /// it came from, since a fridge chip is a bottle as well as an amount.
  final ValueChanged<AmountSuggestion> onPick;

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
              // Fridge and pump chips are marked, because where the number
              // came from changes what it means: the others are habit, these
              // are milk there actually is — on the shelf, or fresh from the
              // pump.
              avatar: switch (s.source) {
                AmountSource.fridge => const Icon(
                  Icons.kitchen_outlined,
                  size: 18,
                ),
                AmountSource.pump => Icon(PumpingFormat.icon, size: 18),
                AmountSource.bottle => null,
              },
              // Says why it is being offered rather than which bottle or
              // session it was, which is the part that matters and the part
              // that stays true when there are two of them.
              tooltip: switch (s.source) {
                AmountSource.fridge => 'In the fridge',
                AmountSource.pump => 'Pumped, not fed yet',
                AmountSource.bottle => null,
              },
              label: Text('${unit.fieldText(s.millilitres)} ${unit.label}'),
              onPressed: () => onPick(s),
            ),
        ],
      ),
    );
  }
}
