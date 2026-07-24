import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/baby.dart';
import '../../data/models/growth_measurement.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/event_tile.dart';
import 'growth_chart.dart';
import 'growth_log_sheet.dart';
import 'growth_metric.dart';
import 'who_percentiles.dart';

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
                final maxAge = points.isEmpty ? 6.0 : points.last.ageMonths;
                final maxMonth = (maxAge.ceil() + 1).clamp(3, 60);
                final curves = baby.sex == null
                    ? const <PercentileCurve>[]
                    : whoPercentileCurves(
                        _metric,
                        baby.sex!,
                        maxMonth: maxMonth,
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
                    if (baby.sex == null) _SetSexBanner(baby: baby),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: GrowthChart(
                        points: points,
                        metric: _metric,
                        curves: curves,
                      ),
                    ),
                    if (baby.sex != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Shaded band: WHO 3rd–97th percentiles',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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

/// Shown when the baby has no recorded sex: WHO percentiles are sex-specific,
/// so we offer a one-tap way to set it (writes to the profile).
class _SetSexBanner extends ConsumerWidget {
  const _SetSexBanner({required this.baby});

  final Baby baby;

  Future<void> _set(WidgetRef ref, BabySex sex) async {
    await ref
        .read(babiesRepositoryProvider)
        ?.updateBaby(baby.copyWith(sex: sex));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set ${baby.name}\'s sex to overlay WHO growth percentiles.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => _set(ref, BabySex.male),
                  child: const Text('Male'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _set(ref, BabySex.female),
                  child: const Text('Female'),
                ),
              ],
            ),
          ],
        ),
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
