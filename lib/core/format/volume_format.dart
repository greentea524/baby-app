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
/// their own for metric, with the fluid-ounce equivalent alongside for US.
///
/// US keeps both because amounts are entered in ml — bottles and pump bags
/// are marked that way — so dropping the ml would hide the number that was
/// actually typed in.
String formatVolume(double ml, UnitSystem units) => units.isMetric
    ? '${_trim(ml)} ml'
    : '${_trim(ml)} ml (${formatFlOz(ml)} fl oz)';
