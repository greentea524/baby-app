import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_mode_provider.dart';

/// Which units measurements are shown and entered in (KAN-182).
///
/// Storage is always metric — kg, cm, ml — because the WHO growth reference
/// is defined in those units and converting at rest would lose precision on
/// every edit. This only changes what the UI renders and what the entry
/// fields expect.
enum UnitSystem {
  us('US', 'lb, in, fl oz'),
  metric('Metric', 'kg, cm, ml');

  const UnitSystem(this.label, this.description);

  final String label;
  final String description;

  bool get isMetric => this == UnitSystem.metric;

  /// Defaults to US, which is what the app displayed before this setting
  /// existed — an existing caregiver shouldn't find their units changed by
  /// an update.
  static UnitSystem fromName(String? name) =>
      values.asNameMap()[name] ?? UnitSystem.us;
}

const _unitSystemKey = 'unit_system';

final unitSystemProvider = NotifierProvider<UnitSystemNotifier, UnitSystem>(
  UnitSystemNotifier.new,
);

class UnitSystemNotifier extends Notifier<UnitSystem> {
  @override
  UnitSystem build() => UnitSystem.fromName(
    ref.read(sharedPreferencesProvider).getString(_unitSystemKey),
  );

  Future<void> setUnits(UnitSystem units) async {
    state = units;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_unitSystemKey, units.name);
  }
}
