import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/fridge_bottle.dart';
import '../../data/repositories/repository_providers.dart';

/// A, B, C or Other, with letters that have another bottle in them greyed
/// out.
///
/// Shared by the fridge's own bottle sheet and Log pumping's "Add to the
/// fridge", so the two follow one rule — see `ShelfLayout.canTake`. Until the
/// fridge has loaded nothing is known about the letters, so only Other is
/// offered.
class FridgeSlotPicker extends ConsumerWidget {
  const FridgeSlotPicker({
    super.key,
    required this.slot,
    required this.onChanged,
    this.bottle,
    this.title,
  });

  final FridgeSlot slot;
  final ValueChanged<FridgeSlot> onChanged;

  /// The bottle being edited, whose own letter stays pickable; null for a
  /// new one.
  final FridgeBottle? bottle;

  /// A heading above the buttons, where the sheet has none of its own.
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final loaded = ref.watch(fridgeBottlesProvider).hasValue;
    final layout = ref.watch(fridgeLayoutProvider);
    bool free(FridgeSlot s) =>
        !s.isLabelled || (loaded && layout.canTake(s, bottle));

    // A letter picked earlier that has since been filled shows as Other —
    // or, for a bottle being edited, as where it already is.
    final own = bottle == null ? null : layout.slotOf(bottle!);
    final shown = free(slot) ? slot : own ?? FridgeSlot.other;
    final empty = [
      for (final s in FridgeSlot.labelled)
        if (loaded && !layout.labelled.containsKey(s)) s.label,
    ];

    final note = !loaded
        ? 'Goes under Other until the fridge has loaded.'
        : empty.isNotEmpty
        ? 'Empty: ${empty.join(', ')}. Taken letters cannot be picked.'
        : bottle == null
        ? 'A, B and C are full, so it goes under Other.'
        : 'No letter is empty. To swap two bottles, drag one onto the '
              'other on the shelf.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final t?) ...[
          Text(t, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
        ],
        SegmentedButton<FridgeSlot>(
          segments: [
            for (final s in FridgeSlot.values)
              ButtonSegment(
                value: s,
                enabled: free(s),
                label: Text(s.label, maxLines: 1, softWrap: false),
              ),
          ],
          selected: {shown},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onChanged(s.first),
        ),
        const SizedBox(height: 4),
        Text(
          note,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
