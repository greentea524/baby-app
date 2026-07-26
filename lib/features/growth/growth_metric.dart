import '../../data/models/growth_measurement.dart';
import 'growth_units.dart';

/// The three tracked growth metrics, with display metadata and pure helpers
/// (kept out of widgets so the chart math is unit-testable).
enum GrowthMetric {
  weight('Weight', 'kg', 'lb'),
  height('Height', 'cm', 'in'),
  head('Head', 'cm', 'in');

  const GrowthMetric(this.label, this.unit, this.displayUnit);

  final String label;

  /// The metric unit values are stored in (matches the WHO reference data).
  final String unit;

  /// The US-customary unit shown to the user.
  final String displayUnit;

  double? valueOf(GrowthMeasurement m) => switch (this) {
    GrowthMetric.weight => m.weightKg,
    GrowthMetric.height => m.heightCm,
    GrowthMetric.head => m.headCm,
  };

  /// Converts a stored (metric) value to its US-customary display value:
  /// pounds for weight, inches for height/head.
  double toDisplay(double metricValue) => switch (this) {
    GrowthMetric.weight => kgToLb(metricValue),
    GrowthMetric.height => cmToIn(metricValue),
    GrowthMetric.head => cmToIn(metricValue),
  };
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
