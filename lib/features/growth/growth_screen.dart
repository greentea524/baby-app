import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/growth_measurement.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/event_tile.dart';
import 'growth_chart.dart';
import 'growth_log_sheet.dart';
import 'growth_metric.dart';

/// Growth tab: log weight/height/head over time (KAN-162) and view the
/// trend chart (KAN-163).
class GrowthScreen extends ConsumerStatefulWidget {
  const GrowthScreen({super.key});

  @override
  ConsumerState<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends ConsumerState<GrowthScreen> {
  GrowthMetric _metric = GrowthMetric.weight;

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(currentBabyProvider);
    final measurementsAsync = ref.watch(growthMeasurementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Growth')),
      floatingActionButton: baby == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showGrowthLog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
      body: baby == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a baby on the Home tab to track growth.'),
              ),
            )
          : measurementsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load: $e')),
              data: (measurements) {
                final points = growthPoints(
                  measurements,
                  _metric,
                  baby.birthDate,
                );
                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SegmentedButton<GrowthMetric>(
                        segments: [
                          for (final m in GrowthMetric.values)
                            ButtonSegment(value: m, label: Text(m.label)),
                        ],
                        selected: {_metric},
                        onSelectionChanged: (s) =>
                            setState(() => _metric = s.first),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: GrowthChart(points: points, metric: _metric),
                    ),
                    const Divider(),
                    if (measurements.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No measurements yet.')),
                      )
                    else
                      for (final m in measurements.reversed)
                        _MeasurementTile(
                          measurement: m,
                          birthDate: baby.birthDate,
                        ),
                  ],
                );
              },
            ),
    );
  }
}

class _MeasurementTile extends ConsumerWidget {
  const _MeasurementTile({required this.measurement, required this.birthDate});

  final GrowthMeasurement measurement;
  final DateTime birthDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = <String>[
      if (measurement.weightKg != null) '${measurement.weightKg} kg',
      if (measurement.heightCm != null) '${measurement.heightCm} cm',
      if (measurement.headCm != null) '${measurement.headCm} cm head',
    ];
    final months = ageInMonths(birthDate, measurement.date);
    final age = months < 1
        ? '${(months * 30.4375).round()}d'
        : '${months.toStringAsFixed(months >= 10 ? 0 : 1)}mo';
    return EventTile(
      key: ValueKey(measurement.id),
      icon: Icons.straighten,
      title:
          '${measurement.date.month}/${measurement.date.day}/${measurement.date.year}',
      subtitle: parts.join(' · '),
      trailing: age,
      confirmTitle: 'Delete measurement?',
      deletedMessage: 'Measurement deleted',
      onTap: () => showGrowthLog(context, existing: measurement),
      onDelete: () async =>
          ref.read(growthRepositoryProvider)?.delete(measurement.id),
    );
  }
}
