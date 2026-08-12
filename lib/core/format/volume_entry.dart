import 'volume_format.dart';

/// The unit a volume is being *typed* in (#—, follows KAN-182).
///
/// Deliberately not tied to the caregiver's unit setting. The unit changes
/// per entry rather than per person — you read whichever is printed on the
/// bottle in front of you — and starting somewhere predictable beats starting
/// somewhere clever.
///
/// Storage stays millilitres either way.
enum VolumeUnit {
  ml('ml'),
  flOz('fl oz');

  const VolumeUnit(this.label);

  final String label;

  /// What every amount field opens in.
  ///
  /// Millilitres regardless of the caregiver's unit setting, because that is
  /// what the thing in your hand is marked in: bottles and pump bags carry ml
  /// even in a US kitchen, and formula scoops are dosed against it. Ounces
  /// are a tap away for anyone reading a bottle the other way round.
  static const initial = VolumeUnit.ml;

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
