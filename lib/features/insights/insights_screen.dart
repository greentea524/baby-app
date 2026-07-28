import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/repositories/repository_providers.dart';
import '../timeline/timeline_format.dart';
import 'insights_providers.dart';
import 'range_stats.dart';
import 'trend_chart.dart';

/// Trends over a week or a month (KAN-166): how feeding, diapers, and
/// pumping move day to day, rather than the single-day view the timeline
/// already gives.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  InsightsRange _range = InsightsRange.week;

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(currentBabyProvider);
    final statsAsync = ref.watch(rangeStatsProvider(_range));

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: baby == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a baby on the Home tab to see trends.'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<InsightsRange>(
                    segments: [
                      for (final r in InsightsRange.values)
                        ButtonSegment(value: r, label: Text(r.label)),
                    ],
                    selected: {_range},
                    onSelectionChanged: (s) => setState(() => _range = s.first),
                  ),
                ),
                Expanded(
                  child: statsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Could not load: $e')),
                    data: (stats) => stats == null
                        ? const SizedBox.shrink()
                        : RefreshIndicator(
                            onRefresh: () async =>
                                ref.invalidate(rangeStatsProvider(_range)),
                            child: _Trends(stats: stats, range: _range),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Trends extends ConsumerWidget {
  const _Trends({required this.stats, required this.range});

  final RangeStats stats;
  final InsightsRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    if (stats.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Nothing logged in the last ${range.days} days.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    final labels = [for (final d in stats.days) '${d.day.month}/${d.day.day}'];

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SummaryGrid(stats: stats),
        const SizedBox(height: 8),
        _ChartSection(
          title: 'Feeds per day',
          values: [for (final d in stats.days) d.stats.feedCount.toDouble()],
          labels: labels,
        ),
        _ChartSection(
          title: 'Diapers per day',
          values: [for (final d in stats.days) d.stats.diaperCount.toDouble()],
          labels: labels,
        ),
        if (stats.totalBottleMl > 0)
          _ChartSection(
            title: units.isMetric
                ? 'Bottle per day (ml)'
                : 'Bottle per day (ml · fl oz)',
            values: [for (final d in stats.days) d.stats.bottleMl],
            labels: labels,
            secondaryFormat: units.isMetric ? null : formatFlOz,
          ),
        if (stats.totalBreastMinutes > 0)
          _ChartSection(
            title: 'Breastfeeding per day (min)',
            values: [
              for (final d in stats.days) d.stats.breastMinutes.toDouble(),
            ],
            labels: labels,
          ),
        if (stats.totalPumpedMl > 0)
          _ChartSection(
            title: units.isMetric
                ? 'Pumped per day (ml)'
                : 'Pumped per day (ml · fl oz)',
            values: [for (final d in stats.days) d.stats.pumpedMl],
            labels: labels,
            secondaryFormat: units.isMetric ? null : formatFlOz,
          ),
      ],
    );
  }
}

/// The headline figures for the whole range.
class _SummaryGrid extends ConsumerWidget {
  const _SummaryGrid({required this.stats});

  final RangeStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    final tiles = <({String label, String value, String? detail})>[
      (
        label: 'Feeds / day',
        value: stats.feedsPerDay.toStringAsFixed(1),
        detail: '${stats.totalFeeds} total',
      ),
      (
        label: 'Avg interval',
        value: TimelineFormat.interval(stats.avgFeedIntervalMinutes),
        detail: null,
      ),
      (
        label: 'Diapers / day',
        value: stats.diapersPerDay.toStringAsFixed(1),
        detail: '${stats.totalDiapers} total',
      ),
      if (stats.totalBottleMl > 0)
        (
          label: 'Bottle total',
          value: '${TimelineFormat.ml(stats.totalBottleMl)} ml',
          detail: units.isMetric
              ? null
              : '${formatFlOz(stats.totalBottleMl)} fl oz',
        ),
      if (stats.totalBreastMinutes > 0)
        (
          label: 'Breast total',
          value: '${stats.totalBreastMinutes} min',
          detail: null,
        ),
      if (stats.totalPumpedMl > 0)
        (
          label: 'Pumped total',
          value: '${TimelineFormat.ml(stats.totalPumpedMl)} ml',
          detail: units.isMetric
              ? null
              : '${formatFlOz(stats.totalPumpedMl)} fl oz',
        ),
    ];

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in tiles)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.label, style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(t.value, style: theme.textTheme.titleMedium),
                  if (t.detail != null)
                    Text(t.detail!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.title,
    required this.values,
    required this.labels,
    this.secondaryFormat,
  });

  final String title;
  final List<double> values;
  final List<String> labels;
  final String Function(double)? secondaryFormat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          TrendChart(
            values: values,
            labels: labels,
            secondaryFormat: secondaryFormat,
          ),
        ],
      ),
    );
  }
}
