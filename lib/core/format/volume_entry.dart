import 'unit_system.dart';
import 'volume_format.dart';

/// The unit a volume is being *typed* in (#—, follows KAN-182).
///
/// Separate from [UnitSystem] because it changes per entry rather than per
/// caregiver: a US kitchen has bottles marked in ounces and pump bags marked
/// in millilitres, and you read whichever one is in front of you. The setting
/// picks the default; this picks what you are holding.
///
/// Storage stays millilitres either way — see [UnitSystem].
enum VolumeUnit {
  ml('ml'),
  flOz('fl oz');

  const VolumeUnit(this.label);

  final String label;

  /// What to offer first for a caregiver on [system].
  static VolumeUnit defaultFor(UnitSystem system) =>
      system.isMetric ? VolumeUnit.ml : VolumeUnit.flOz;

  /// A typed amount, in millilitres.
  double toMl(double typed) =>
      this == VolumeUnit.ml ? typed : flOzToMl(typed);

  /// A stored amount, in this unit.
  double fromMl(double millilitres) =>
      this == VolumeUnit.ml ? millilitres : mlToFlOz(millilitres);

  /// [millilitres] as an editable string in this unit.
  ///
  /// One decimal at most, and no trailing ".0" — a field that opens reading
  /// "120.0" invites you to delete two characters before typing.
  String fieldText(double millilitres) {
    final value = fromMl(millilitres);
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }
}
