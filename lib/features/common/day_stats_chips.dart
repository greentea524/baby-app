import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../timeline/day_stats.dart';
import '../timeline/timeline_format.dart';

/// The at-a-glance figures for a single day, as a wrap of chips.
///
/// Shared by the timeline and Home so the two can't drift — the numbers mean
/// the same thing in both places, and Home showing a different set would just
/// be a second thing to keep in step.
class DayStatsChips extends ConsumerWidget {
  const DayStatsChips({super.key, required this.stats});

  final DayStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    final diaperDetail = [
      if (stats.wetCount > 0) '${stats.wetCount} wet',
      if (stats.dirtyCount > 0) '${stats.dirtyCount} dirty',
      if (stats.bothCount > 0) '${stats.bothCount} both',
    ].join(', ');

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatChip(
          icon: Icons.restaurant,
          label: 'Feeds',
          value: '${stats.feedCount}',
        ),
        StatChip(
          icon: Icons.timelapse,
          label: 'Avg interval',
          value: TimelineFormat.interval(stats.avgFeedIntervalMinutes),
        ),
        if (stats.breastMinutes > 0)
          StatChip(
            icon: Icons.child_friendly,
            label: 'Breast',
            value: '${stats.breastMinutes} min',
          ),
        if (stats.bottleMl > 0)
          StatChip(
            icon: Icons.local_drink,
            label: 'Bottle',
            value: '${TimelineFormat.ml(stats.bottleMl)} ml',
            detail: units.isMetric
                ? null
                : '${formatFlOz(stats.bottleMl)} fl oz',
          ),
        if (stats.pumpCount > 0)
          StatChip(
            icon: Icons.opacity,
            label: 'Pumped',
            value: '${TimelineFormat.ml(stats.pumpedMl)} ml',
            detail: units.isMetric
                ? '${stats.pumpCount}x'
                : '${stats.pumpCount}x · ${formatFlOz(stats.pumpedMl)} fl oz',
          ),
        StatChip(
          icon: Icons.baby_changing_station,
          label: 'Diapers',
          value: '${stats.diaperCount}',
          detail: diaperDetail.isEmpty ? null : diaperDetail,
        ),
      ],
    );
  }
}

/// One figure: icon, caption, value, and an optional supporting line.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailText = detail;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium),
          if (detailText != null)
            Text(detailText, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
