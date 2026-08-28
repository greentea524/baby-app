import 'package:flutter/material.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../timeline/timeline_format.dart';
import 'range_stats.dart';

/// The export report's tables, on screen (#30).
///
/// The same overview and per-day layout the PDF prints, which reads better
/// than the charts for "what actually happened" and was previously only
/// reachable by generating a file.
///
/// Takes a [RangeStats] and nothing else — every figure here is one Insights
/// already has, so switching to this view costs no fetch and no recompute.
class ReportTables extends StatelessWidget {
  const ReportTables({super.key, required this.stats, required this.units});

  final RangeStats stats;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle('Day by day'),
          const SizedBox(height: 8),
          _DailyTable(stats: stats, units: units),
          const SizedBox(height: 24),
          // Under the days rather than over them: the table is what the view
          // is for, and a summary reads as a summary when it comes after the
          // thing it summarises.
          _SectionTitle('Overview'),
          const SizedBox(height: 8),
          _Overview(stats: stats, units: units),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Label and figure, one pair per row.
///
/// Rows that would read zero for everyone are left out rather than printed,
/// exactly as the PDF does: a family that does not pump should not have to
/// read two rows saying so.
class _Overview extends StatelessWidget {
  const _Overview({required this.stats, required this.units});

  final RangeStats stats;
  final UnitSystem units;

  String _volume(double ml) => units.isMetric
      ? '${TimelineFormat.ml(ml)} ml'
      : '${TimelineFormat.ml(ml)} ml (${formatFlOz(ml)} fl oz)';

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Total feeds', '${stats.totalFeeds}'),
      ('Feeds per day (avg)', stats.feedsPerDay.toStringAsFixed(1)),
      (
        'Avg interval between feeds',
        TimelineFormat.interval(stats.avgFeedIntervalMinutes),
      ),
      ('Bottle total', _volume(stats.totalBottleMl)),
      ('Breastfeeding total', '${stats.totalBreastMinutes} min'),
      // Its own rows, never folded into the bottle total: pumping is output
      // from the parent, and the same milk usually comes back as a bottle
      // already counted above.
      if (stats.totalPumps > 0) ...[
        ('Pump sessions', '${stats.totalPumps}'),
        ('Pumped total', _volume(stats.totalPumpedMl)),
      ],
      // Apart from the feed count on purpose: a feeds-per-day figure should
      // not have top-ups folded into it, though the volume above does.
      if (stats.totalSnacks > 0)
        ('Snacks / top-ups', '${stats.totalSnacks} (not counted as feeds)'),
      ('Total diaper changes', '${stats.totalDiapers}'),
      ('Days with activity', '${stats.activeDays} of ${stats.days.length}'),
    ];

    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: i == 0
                    ? BorderSide(color: theme.dividerColor)
                    : BorderSide.none,
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(rows[i].$1, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(width: 12),
                Text(
                  rows[i].$2,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One row per day, scrolling sideways.
///
/// Breast minutes are deliberately absent. The column was carried over from
/// the printed report, where a paediatrician reading a page wants it; on
/// screen it was a column of zeros for a bottle-fed baby and one more thing
/// to scroll past for everyone else. The range total is still in the overview
/// below, which is where a figure nobody reads per-day belongs.
///
/// Still wider than a phone, so it keeps its own horizontal scroll rather
/// than being allowed to squeeze or overflow — the discipline the charts
/// already follow.
class _DailyTable extends StatelessWidget {
  const _DailyTable({required this.stats, required this.units});

  final RangeStats stats;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The column goes entirely for a family that does not pump, rather than
    // running a stripe of zeros down the whole table.
    final pumped = stats.totalPumps > 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 52,
        columnSpacing: 20,
        columns: [
          const DataColumn(label: Text('Date')),
          const DataColumn(label: Text('Feeds'), numeric: true),
          const DataColumn(label: Text('Bottle (ml)'), numeric: true),
          if (!units.isMetric)
            const DataColumn(label: Text('Bottle (fl oz)'), numeric: true),
          if (pumped)
            const DataColumn(label: Text('Pumped (ml)'), numeric: true),
          const DataColumn(label: Text('Diapers'), numeric: true),
        ],
        rows: [
          for (final row in stats.days)
            DataRow(
              cells: [
                DataCell(Text(TimelineFormat.shortDate(row.day))),
                DataCell(Text('${row.stats.feedCount}')),
                DataCell(Text(TimelineFormat.ml(row.stats.bottleMl))),
                if (!units.isMetric)
                  DataCell(
                    Text(
                      // Blank rather than "0.0": an empty cell reads as
                      // nothing happened, which is what it means.
                      row.stats.bottleMl == 0
                          ? ''
                          : formatFlOz(row.stats.bottleMl),
                    ),
                  ),
                if (pumped)
                  DataCell(Text(TimelineFormat.ml(row.stats.pumpedMl))),
                DataCell(Text('${row.stats.diaperCount}')),
              ],
            ),
        ],
        headingTextStyle: theme.textTheme.labelLarge,
        dataTextStyle: theme.textTheme.bodyMedium,
      ),
    );
  }
}
