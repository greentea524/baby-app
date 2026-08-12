/// Volume formatting shared across feeding, pumping, the timeline, and
/// exports. Amounts are entered and stored in millilitres; US fluid ounces
/// are shown alongside for readers who prefer US units.
library;

import 'unit_system.dart';

/// One US fluid ounce in millilitres.
const double _mlPerFlOz = 29.5735295625;

/// Millilitres -> US fluid ounces.
double mlToFlOz(double ml) => ml / _mlPerFlOz;

/// Rounds to one decimal and trims a trailing ".0" so numbers read cleanly.
String _trim(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
}

/// Millilitres trimmed of a trailing ".0", e.g. "120" or "62.5".
String formatMl(double ml) => _trim(ml);

/// US fluid ounces (one decimal), e.g. "4.1".
String formatFlOz(double ml) => _trim(mlToFlOz(ml));

/// A stored volume rendered for the caregiver's chosen units: millilitres on
/// their own for metric, ounces leading with millilitres alongside for US.
///
/// US leads with ounces now that ounces can be typed in. Reading back
/// "147.9 ml (5 fl oz)" a second after entering 5 makes the app look like it
/// changed the number.
///
/// Both are kept either way: bottles and pump bags are marked in millilitres
/// as often as not, and dropping them would hide the figure on the thing in
/// front of you.
String formatVolume(double ml, UnitSystem units) => units.isMetric
    ? '${_trim(ml)} ml'
    : '${formatFlOz(ml)} fl oz (${_trim(ml)} ml)';

/// US fluid ounces -> millilitres. The inverse of [mlToFlOz], for turning a
/// typed amount back into what gets stored.
double flOzToMl(double flOz) => flOz * _mlPerFlOz;
