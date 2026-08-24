import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/activity_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../activity/activity_filter.dart';
import '../activity/activity_tile.dart';
import 'day_stats.dart';
import 'timeline_format.dart';

/// Daily timeline with day navigation, a stats summary, and a chronological
/// list of feeds + diaper changes (KAN-132).
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final feedsAsync = ref.watch(feedingsForDayProvider);
    final diapersAsync = ref.watch(diapersForDayProvider);
    final pumpsAsync = ref.watch(pumpingForDayProvider);
    final baby = ref.watch(currentBabyProvider);

    final loading =
        (!feedsAsync.hasValue && feedsAsync.isLoading) ||
        (!diapersAsync.hasValue && diapersAsync.isLoading) ||
        (!pumpsAsync.hasValue && pumpsAsync.isLoading);

    final feeds = feedsAsync.value ?? const [];
    final diapers = diapersAsync.value ?? const [];
    final pumps = pumpsAsync.value ?? const [];
    final entries = mergeActivities(
      feeds,
      diapers,
      pumps: pumps,
      descending: false,
    );
    final filter = ref.watch(activityFilterProvider);
    final visible = applyActivityFilter(entries, filter);
    // Stats stay on the whole day on purpose: the card summarises what
    // happened, while the filter is about what you are reading through. A
    // filtered summary would quietly under-report the day.
    final stats = DayStats.from(feeds, diapers, pumps: pumps);

    return Scaffold(
      // The day navigation lives in the app bar rather than in a row of its
      // own beneath it. The bar was showing the word "Timeline" — which the
      // tab underneath already says — and spending a whole row to do it,
      // while the list below fought for what was left.
      appBar: _DayAppBar(day: day),
      body: baby == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a baby on the Home tab to see the timeline.'),
              ),
            )
          : loading
          ? const Center(child: CircularProgressIndicator())
          // One scroll view, so the stats can move out of the way. They were
          // fixed above an Expanded list: seven chips wrapping to three rows
          // on a phone took most of the screen and left the list reading
          // through a slot, on exactly the busy days with most to read.
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _StatsCard(stats: stats)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedFilterBar(
                    height: ActivityFilterBar.barHeight(context) + 1,
                    background: Theme.of(context).colorScheme.surface,
                  ),
                ),
                if (entries.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No events on this day.'),
                      ),
                    ),
                  )
                // Distinct from an empty day: there *is* activity, just none
                // of this kind, and saying so points at the filter.
                else if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No ${filter.label.toLowerCase()} on this day.',
                        ),
                      ),
                    ),
                  )
                else
                  SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => ActivityTile(
                      entry: visible[i],
                      // The day is already in the app bar above, so the bare
                      // clock time is enough here.
                      timeDisplay: ActivityTimeDisplay.clock,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Keeps the kind filter reachable once the stats have scrolled away.
///
/// The list is the reason to be on this screen, so everything above it earns
/// its place: the stats are read once and go, the filter has to stay.
class _PinnedFilterBar extends SliverPersistentHeaderDelegate {
  const _PinnedFilterBar({required this.height, required this.background});

  final double height;
  final Color background;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    // Opaque, or the rows scroll visibly through it. Sized explicitly because
    // a child shorter than the extent trips "layoutExtent exceeds
    // paintExtent"; the divider takes up the spare point.
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: background,
        child: const Column(
          children: [
            Expanded(child: ActivityFilterBar()),
            Divider(height: 1),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_PinnedFilterBar old) =>
      old.height != height || old.background != background;
}

/// The app bar, carrying the day and the way to move between days.
class _DayAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _DayAppBar({required this.day});

  final DateTime day;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  bool get _isToday {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  void _shift(WidgetRef ref, int days) {
    ref.read(selectedDayProvider.notifier).shift(days);
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) {
      ref.read(selectedDayProvider.notifier).setDay(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      // The leading slot is left to the framework on purpose. The timeline is
      // pushed over Home rather than being a tab, so that slot holds the back
      // button — and putting the previous-day chevron there, as this bar
      // briefly did, left the screen with no way out of it.
      titleSpacing: 0,
      title: TextButton.icon(
        icon: const Icon(Icons.calendar_today, size: 18),
        label: Text(
          TimelineFormat.dayLabel(day),
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: () => _pick(context, ref),
      ),
      // Both day controls together on the right. Paired is how they read —
      // and it keeps a second left-pointing chevron away from the back
      // button, where the two would be one glance apart and mean different
      // things.
      actions: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _shift(ref, -1),
          tooltip: 'Previous day',
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _isToday ? null : () => _shift(ref, 1),
          tooltip: 'Next day',
        ),
      ],
    );
  }
}

class _StatsCard extends ConsumerWidget {
  const _StatsCard({required this.stats});

  final DayStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);
    final diaperDetail = [
      if (stats.wetCount > 0) '${stats.wetCount} wet',
      if (stats.dirtyCount > 0) '${stats.dirtyCount} dirty',
      if (stats.bothCount > 0) '${stats.bothCount} both',
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatChip(
            icon: Icons.restaurant,
            label: 'Feeds',
            value: '${stats.feedCount}',
          ),
          _StatChip(
            icon: Icons.timelapse,
            label: 'Avg interval',
            value: TimelineFormat.interval(stats.avgFeedIntervalMinutes),
          ),
          // Only when there were any: a permanent "Snacks 0" would be noise
          // for the many days that have none.
          if (stats.snackCount > 0)
            _StatChip(
              icon: Icons.cookie_outlined,
              label: 'Snacks',
              value: '${stats.snackCount}',
              detail: 'not counted as feeds',
            ),
          if (stats.breastMinutes > 0)
            _StatChip(
              icon: Icons.child_friendly,
              label: 'Breast',
              value: '${stats.breastMinutes} min',
            ),
          if (stats.bottleMl > 0)
            _StatChip(
              icon: Icons.local_drink,
              label: 'Bottle',
              value: '${TimelineFormat.ml(stats.bottleMl)} ml',
              detail: units.isMetric
                  ? null
                  : '${formatFlOz(stats.bottleMl)} fl oz',
            ),
          if (stats.pumpCount > 0)
            _StatChip(
              icon: Icons.opacity,
              label: 'Pumped',
              value: '${TimelineFormat.ml(stats.pumpedMl)} ml',
              detail: units.isMetric
                  ? '${stats.pumpCount}x'
                  : '${stats.pumpCount}x · ${formatFlOz(stats.pumpedMl)} fl oz',
            ),
          _StatChip(
            icon: Icons.baby_changing_station,
            label: 'Diapers',
            value: '${stats.diaperCount}',
            detail: diaperDetail.isEmpty ? null : diaperDetail,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // One line, and min width. Stacked over three lines each, at full
          // width apiece, seven chips came to 518pt of summary above a list
          // with nowhere left to go: the Row defaulted to MainAxisSize.max,
          // so every chip filled the Wrap and took a row to itself.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 5),
              // Flexible, because putting the label beside the value rather
              // than above it means the pair has to fit across a chip: at
              // 200% on a narrow phone "3h 10m Avg interval" ran 77pt past
              // the edge. It wraps rather than truncates — the label is the
              // half that says what the number is.
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          // Kept on its own line rather than run into the one above: only
          // three of the chips have one, and inline it would widen those
          // enough to cost a row of its own.
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
