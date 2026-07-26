/// Volume formatting shared across feeding, pumping, the timeline, and
/// exports. Amounts are entered and stored in millilitres; US fluid ounces
/// are shown alongside for readers who prefer US units.
library;

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

/// Both units together, e.g. "120 ml (4.1 fl oz)".
String formatVolume(double ml) => '${_trim(ml)} ml (${formatFlOz(ml)} fl oz)';
