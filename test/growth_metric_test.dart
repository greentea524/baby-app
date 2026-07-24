import 'package:baby_app/data/models/growth_measurement.dart';
import 'package:baby_app/features/growth/growth_metric.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final birth = DateTime(2026, 1, 1);

  test('ageInMonths converts elapsed time to months', () {
    // ~6 months later.
    expect(ageInMonths(birth, DateTime(2026, 7, 1)), closeTo(5.95, 0.1));
    expect(ageInMonths(birth, birth), 0);
  });

  test('growthPoints extracts and sorts non-null values for a metric', () {
    final measurements = [
      GrowthMeasurement(
        id: 'b',
        date: DateTime(2026, 4, 1),
        weightKg: 6.0,
        heightCm: 60,
      ),
      GrowthMeasurement(id: 'a', date: DateTime(2026, 2, 1), weightKg: 4.5),
      GrowthMeasurement(
        id: 'c',
        date: DateTime(2026, 3, 1),
        headCm: 40, // no weight -> excluded from weight points
      ),
    ];

    final weight = growthPoints(measurements, GrowthMetric.weight, birth);
    expect(weight.map((p) => p.value).toList(), [4.5, 6.0]); // sorted by age
    expect(weight.first.ageMonths, lessThan(weight.last.ageMonths));

    final head = growthPoints(measurements, GrowthMetric.head, birth);
    expect(head.length, 1);
    expect(head.first.value, 40);
  });
}
