/// US-customary conversions for the growth feature.
///
/// Measurements are stored in metric (kg/cm) to match the WHO reference data;
/// these helpers convert to/from US units for display and data entry.
library;

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

/// Combines whole pounds and ounces into kilograms.
double lbOzToKg(int lb, double oz) => lbToKg(lb + oz / 16);

/// A weight formatted as e.g. "13 lb 4 oz".
String formatLbOz(double kg) {
  final w = kgToLbOz(kg);
  return '${w.lb} lb ${w.oz} oz';
}
