import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/fridge_bottle.dart';

const _key = 'fridge_vessel';

/// What the last bottle added on this device was kept in, which the next one
/// starts on: a household that stores milk in containers uses them every
/// time, and choosing again for each would be a tap spent saying the same
/// thing. A bottle until anything else has been chosen.
final lastVesselProvider = NotifierProvider<LastVesselNotifier, Vessel>(
  LastVesselNotifier.new,
);

class LastVesselNotifier extends Notifier<Vessel> {
  @override
  Vessel build() =>
      Vessel.fromName(ref.read(sharedPreferencesProvider).getString(_key));

  Future<void> set(Vessel vessel) async {
    if (vessel == state) return;
    state = vessel;
    await ref.read(sharedPreferencesProvider).setString(_key, vessel.name);
  }
}

/// Bottle or container: one segment each, as [MilkChooser] asks its
/// question.
class VesselChooser extends StatelessWidget {
  const VesselChooser({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Vessel value;
  final ValueChanged<Vessel> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Vessel>(
      segments: [
        for (final v in Vessel.values)
          ButtonSegment(
            value: v,
            label: Text(v.label, maxLines: 1, softWrap: false),
          ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
