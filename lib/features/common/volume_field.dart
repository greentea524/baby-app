import 'package:flutter/material.dart';

import '../../core/format/volume_entry.dart';
import 'number_input.dart';

/// An amount field with a unit beside it, shared by the bottle and pumping
/// forms.
///
/// Switching the unit converts what is already typed rather than
/// reinterpreting it: 150 ml becomes 5.1 fl oz, not 150 fl oz. The volume in
/// the field is the volume you meant, whichever way you are reading it off
/// the bottle.
class VolumeField extends StatelessWidget {
  const VolumeField({
    super.key,
    required this.controller,
    required this.unit,
    required this.onUnitChanged,
    required this.onChanged,
    this.label = 'Amount',
    this.errorText,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final VolumeUnit unit;

  /// Called with the new unit *and* the converted text, so the caller keeps
  /// the single source of truth for both.
  final void Function(VolumeUnit unit, String text) onUnitChanged;

  /// Fires only on typing, not on a unit switch — the caller uses it to tell
  /// an edited amount from one merely re-rendered in another unit.
  final ValueChanged<String> onChanged;

  final String label;
  final String? errorText;
  final bool autofocus;

  void _switchTo(VolumeUnit next) {
    if (next == unit) return;
    final typed = double.tryParse(controller.text.trim());
    // An empty or unparseable field just changes unit; there is no value to
    // carry across, and blanking what someone half-typed would be rude.
    onUnitChanged(
      next,
      typed == null ? controller.text : next.fieldText(unit.toMl(typed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: positiveDecimalInput,
            decoration: InputDecoration(
              labelText: label,
              suffixText: unit.label,
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        // Sized to the field's own height so the two read as one control,
        // and pinned to the top so an error message below the field pushes
        // neither of them.
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SegmentedButton<VolumeUnit>(
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -2, vertical: -2),
            ),
            showSelectedIcon: false,
            segments: [
              for (final u in VolumeUnit.values)
                ButtonSegment(value: u, label: Text(u.label)),
            ],
            selected: {unit},
            onSelectionChanged: (s) => _switchTo(s.first),
          ),
        ),
      ],
    );
  }
}
