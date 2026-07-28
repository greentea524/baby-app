import '../../core/format/unit_system.dart';
import '../../data/models/growth_measurement.dart';
import 'growth_units.dart';

/// The three tracked growth metrics, with display metadata and pure helpers
/// (kept out of widgets so the chart math is unit-testable).
enum GrowthMetric {
  weight('Weight', 'kg'),
  height('Height', 'cm'),
  head('Head', 'cm');

  const GrowthMetric(this.label, this.unit);

  final String label;

  /// The metric unit values are stored in (matches the WHO reference data).
  final String unit;

  bool get isWeight => this == GrowthMetric.weight;

  double? valueOf(GrowthMeasurement m) => switch (this) {
    GrowthMetric.weight => m.weightKg,
    GrowthMetric.height => m.heightCm,
    GrowthMetric.head => m.headCm,
  };

  /// The axis unit for [units] — "kg"/"cm" or "lb"/"in".
  String displayUnit(UnitSystem units) =>
      units.isMetric ? unit : (isWeight ? 'lb' : 'in');

  /// Converts a stored (metric) value into [units] for display. Metric is a
  /// no-op, since that's what is stored.
  double toDisplay(double metricValue, UnitSystem units) => units.isMetric
      ? metricValue
      : (isWeight ? kgToLb(metricValue) : cmToIn(metricValue));
}

/// Average days per month (365.25 / 12), used to convert a date to the
/// baby's age in months for the growth chart's x-axis.
const double _daysPerMonth = 30.4375;

double ageInMonths(DateTime birthDate, DateTime date) =>
    date.difference(birthDate).inHours / 24 / _daysPerMonth;

/// One plotted point: the baby's age (months) and the metric value.
typedef GrowthPoint = ({double ageMonths, double value});

/// Extracts sorted, non-null points for [metric] from [measurements].
List<GrowthPoint> growthPoints(
  List<GrowthMeasurement> measurements,
  GrowthMetric metric,
  DateTime birthDate,
) {
  final points = <GrowthPoint>[
    for (final m in measurements)
      if (metric.valueOf(m) case final v?)
        (ageMonths: ageInMonths(birthDate, m.date), value: v),
  ]..sort((a, b) => a.ageMonths.compareTo(b.ageMonths));
  return points;
}
