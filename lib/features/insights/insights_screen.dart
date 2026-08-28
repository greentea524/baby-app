import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/feeding_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../timeline/timeline_format.dart';
import 'day_timeline_strip.dart';
import 'day_view_data.dart';
import 'diaper_mix_bar.dart';
import 'feed_pattern_data.dart';
import 'insights_providers.dart';
import 'range_stats.dart';
import 'report_tables.dart';
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

  /// Charts or the report tables. Two ways of reading the same window, so
  /// this sits beside the range picker rather than replacing it (#30).
  bool _asTable = false;

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(currentBabyProvider);
    final statsAsync = ref.watch(rangeStatsProvider(_range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          // Pull-to-refresh below needs a touch drag, which a mouse cannot
          // do — and this app is web-first.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: baby == null
                ? null
                : () => ref.invalidate(rangeStatsProvider(_range)),
          ),
        ],
      ),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 4, 16),
                  child: Row(
                    children: [
                      Flexible(
                        child: SegmentedButton<InsightsRange>(
                          segments: [
                            for (final r in InsightsRange.values)
                              ButtonSegment(value: r, label: Text(r.label)),
                          ],
                          selected: {_range},
                          onSelectionChanged: (s) =>
                              setState(() => _range = s.first),
                        ),
                      ),
                      // Icons rather than a second segmented row: three
                      // ranges leave room beside them, and this is the same
                      // trade _RecentHeader makes on Home.
                      //
                      // Hidden for a single day, where the table would be one
                      // row and the screen shows a different set of charts
                      // anyway.
                      if (!_range.isSingleDay) ...[
                        IconButton(
                          icon: const Icon(Icons.insights),
                          tooltip: 'Charts',
                          isSelected: !_asTable,
                          onPressed: () => setState(() => _asTable = false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.table_rows_outlined),
                          tooltip: 'Table',
                          isSelected: _asTable,
                          onPressed: () => setState(() => _asTable = true),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: statsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Could not load: $e')),
                    data: (data) => data == null
                        ? const SizedBox.shrink()
                        : RefreshIndicator(
                            onRefresh: () async =>
                                ref.invalidate(rangeStatsProvider(_range)),
                            // A day is a different question from a trend, so
                            // it gets different charts rather than the same
                            // ones with one bar in them.
                            child: _range.isSingleDay
                                ? _Today(data: data)
                                : _asTable
                                // The same stats the charts are drawn from,
                                // so switching costs no fetch and no
                                // recompute.
                                ? ListView(
                                    children: [
                                      ReportTables(
                                        stats: data.stats,
                                        units: ref.watch(unitSystemProvider),
                                      ),
                                    ],
                                  )
                                : _Trends(
                                    stats: data.stats,
                                    feedings: data.feedings,
                                    range: _range,
                                  ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Trends extends ConsumerWidget {
  const _Trends({
    required this.stats,
    required this.feedings,
    required this.range,
  });

  final RangeStats stats;
  final List<FeedingEvent> feedings;
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
    final nights = nightStretchMinutes(
      days: [for (final d in stats.days) d.day],
      feedings: feedings,
    );
    final byHour = feedsByHour(feedings);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SummaryGrid(
          stats: stats,
          bestNightMinutes: nights.isEmpty
              ? null
              : nights.reduce((a, b) => a > b ? a : b),
        ),
        const SizedBox(height: 8),
        if (stats.totalFeeds > 0) ...[
          _ChartSection(
            title: 'Longest night stretch',
            subtitle:
                'Between milk feeds, '
                '${hourLabel(nightStartHour)}–${hourLabel(nightEndHour)}',
            values: [for (final m in nights) m.toDouble()],
            labels: labels,
            valueFormat: (v) => TimelineFormat.interval(v.round()),
            // "13h 12m" does not fit the axis gutter; the caption still
            // spells the tapped night out in full.
            axisFormat: (v) => '${(v / 60).toStringAsFixed(1)}h',
          ),
          _ChartSection(
            title: 'Feeds by hour of day',
            subtitle: 'All ${range.days} days stacked together',
            values: [for (final c in byHour) c.toDouble()],
            labels: [for (var h = 0; h < 24; h++) hourLabel(h)],
          ),
        ],
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

/// One day: when things happened, and what was in the diapers.
///
/// The trend charts are deliberately absent. They plot a bar per day, so at a
/// range of one they are a single bar — a number drawn slowly. What a day
/// actually wants answering is *when*, which is what the strip is for.
class _Today extends ConsumerWidget {
  const _Today({required this.data});

  final InsightsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    // The range fetch covers only the day being viewed, so the last dirty
    // diaper before today is not in it. The recent stream is already
    // subscribed by Home and reaches back far enough, so this costs nothing.
    final recent = ref.watch(recentDiapersProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SummaryGrid(stats: data.stats),
        const SizedBox(height: 8),
        _DaySection(
          title: 'Through the day',
          subtitle: 'Every entry, midnight to midnight',
          child: DayTimelineStrip(
            marks: dayMarks(
              day: today,
              feedings: data.feedings,
              diapers: data.diapers,
              pumps: data.pumps,
            ),
          ),
        ),
        _DaySection(
          title: 'Diapers',
          child: DiaperMixBar(
            mix: diaperMix(data.diapers),
            lastWithPoop: lastWithPoop(recent),
            now: today,
          ),
        ),
        if (data.stats.totalFeeds == 0 && data.diapers.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Text(
              'Nothing logged today yet.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// A titled block on the day view, matching [_ChartSection]'s spacing so the
/// two ranges do not look like different screens.
class _DaySection extends StatelessWidget {
  const _DaySection({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// The headline figures for the whole range.
class _SummaryGrid extends ConsumerWidget {
  const _SummaryGrid({required this.stats, this.bestNightMinutes});

  final RangeStats stats;

  /// The best night in the range, kept as a tile because it is the one figure
  /// people want without reading a chart.
  final int? bestNightMinutes;

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
      if (bestNightMinutes != null && bestNightMinutes! > 0)
        (
          label: 'Best night',
          value: TimelineFormat.interval(bestNightMinutes),
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
    this.subtitle,
    this.valueFormat,
    this.axisFormat,
    this.secondaryFormat,
  });

  final String title;
  final List<double> values;
  final List<String> labels;

  /// Says what the bars are measured over when the title can't carry it —
  /// the night window, or that the range is stacked rather than daily.
  final String? subtitle;

  final String Function(double)? valueFormat;
  final String Function(double)? axisFormat;
  final String Function(double)? secondaryFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 4),
          TrendChart(
            // The heading above is drawn, not spoken by the chart — passing
            // it in is what lets the chart say what it is a chart *of*.
            title: title,
            subtitle: subtitle,
            values: values,
            labels: labels,
            valueFormat: valueFormat,
            axisFormat: axisFormat,
            secondaryFormat: secondaryFormat,
          ),
        ],
      ),
    );
  }
}
