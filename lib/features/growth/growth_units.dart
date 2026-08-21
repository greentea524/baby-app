/// US-customary conversions for the growth feature.
///
/// Measurements are stored in metric (kg/cm) to match the WHO reference data;
/// these helpers convert to/from US units for display and data entry.
library;

import '../../core/format/unit_system.dart';

const double _lbPerKg = 2.2046226218487757;
const double _kgPerLb = 0.45359237;
const double _inPerCm = 0.39370078740157477;
const double _cmPerIn = 2.54;

/// kg -> pounds (decimal).
double kgToLb(double kg) => kg * _lbPerKg;

/// pounds (decimal) -> kg.
double lbToKg(double lb) => lb * _kgPerLb;

/// cm -> inches.
double cmToIn(double cm) => cm * _inPerCm;

/// inches -> cm.
double inToCm(double inches) => inches * _cmPerIn;

/// A weight split into whole pounds and whole (rounded) ounces.
typedef LbOz = ({int lb, int oz});

/// Splits [kg] into pounds + ounces, rounded to the nearest ounce (carrying
/// 16 oz up to a pound).
LbOz kgToLbOz(double kg) {
  final totalOz = (kgToLb(kg) * 16).round();
  return (lb: totalOz ~/ 16, oz: totalOz % 16);
}

/// Combines pounds and ounces into kilograms.
///
/// [lb] takes a fraction on purpose. The sheet offers a pounds field and an
/// ounces field because that is how a paediatrician reports a weight, but
/// plenty of scales — and plenty of notes written down at home — say
/// "7.5 lb". Half a pound is eight ounces, and it used to be thrown away:
/// the field was truncated to a whole number before it got here, so 7.5
/// stored as 7 and 227 grams vanished without a word.
double lbOzToKg(double lb, double oz) => lbToKg(lb + oz / 16);

/// The weight to store, in kilograms, given what the fields hold.
///
/// [stored] is what the record held when the sheet opened and [edited] says
/// whether the caregiver has since retyped it. An untouched field is written
/// back unchanged rather than re-read: the fields show a rounded version of
/// the measurement — whole ounces, or kilograms to one decimal — so parsing
/// the text back is not the same as reading the record. Open a 7.4 lb entry,
/// save it without touching it, and re-reading would shave 11 grams off a
/// number nobody edited.
///
/// [pounds] may carry a fraction: a scale reading "7.5 lb" is half a pound,
/// which is eight ounces, and it is added on top of whatever [ounces] holds.
double? weightToStore({
  required bool metric,
  required double? stored,
  required bool edited,
  required double? kilograms,
  required double? pounds,
  required double? ounces,
}) {
  if (!edited && stored != null) return stored;
  if (metric) return kilograms;
  if (pounds == null && ounces == null) return null;
  return lbOzToKg(pounds ?? 0, ounces ?? 0);
}

/// A weight formatted as e.g. "13 lb 4 oz".
String formatLbOz(double kg) {
  final w = kgToLbOz(kg);
  return '${w.lb} lb ${w.oz} oz';
}

/// Rounds to one decimal and drops a trailing ".0".
String trimNumber(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
}

/// A stored weight (kg) rendered in the caregiver's units — "6.4 kg" or
/// "14 lb 2 oz".
String formatWeight(double kg, UnitSystem units) =>
    units.isMetric ? '${trimNumber(kg)} kg' : formatLbOz(kg);

/// A stored length (cm) rendered in the caregiver's units — "62.5 cm" or
/// "24.6 in".
String formatLength(double cm, UnitSystem units) => units.isMetric
    ? '${trimNumber(cm)} cm'
    : '${cmToIn(cm).toStringAsFixed(1)} in';
