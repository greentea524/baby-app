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
  double toMl(double typed) => this == VolumeUnit.ml ? typed : flOzToMl(typed);

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

/// The millilitres an amount field should store.
///
/// [typed] is what the field currently holds, parsed, or null when it is
/// empty or unparseable. [storedMl] is what the entry already had, and
/// [edited] says whether the field has actually been typed in since.
///
/// An amount nobody retyped is stored back untouched. Re-parsing it would
/// round-trip through the display unit — 150 ml shown as 5.1 fl oz, read back
/// as 150.8 — so correcting a note would quietly rewrite a number nobody
/// touched. It settles there rather than walking further on each edit, which
/// makes it a wrong value rather than a runaway one; still not ours to write.
///
/// The same escape hatch lets a form set an exact amount that its own field
/// cannot spell: a suggested 120 ml chip reads "4.1" in fluid ounces, and
/// storing what that parses back to would save 121.3 (#31).
double? resolveAmountMl({
  required double? typed,
  required VolumeUnit unit,
  required double? storedMl,
  required bool edited,
}) {
  if (!edited && storedMl != null) return storedMl;
  return typed == null ? null : unit.toMl(typed);
}
