import 'package:flutter/material.dart';

import '../../data/models/milk_kind.dart';

/// Breast milk, formula or whole milk: one segment each.
///
/// Shared by the bottle feed and the fridge's own sheet, so the two ask the
/// question the same way. Labels without icons, because three icons and
/// three labels do not fit across a phone at the larger text sizes, and the
/// words are the part that is read.
///
/// [value] may be null — a feed logged before the question was asked — and
/// then nothing is selected until something is picked. Once something is,
/// it cannot be unpicked back to nothing: "unknown" is only ever history.
class MilkChooser extends StatelessWidget {
  const MilkChooser({super.key, required this.value, required this.onChanged});

  final MilkKind? value;
  final ValueChanged<MilkKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MilkKind>(
      segments: [
        for (final k in MilkKind.values)
          ButtonSegment(
            value: k,
            label: Text(k.label, maxLines: 1, softWrap: false),
          ),
      ],
      selected: {?value},
      emptySelectionAllowed: value == null,
      showSelectedIcon: false,
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
    );
  }
}
