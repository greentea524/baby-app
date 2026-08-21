import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/activity_entry.dart';

/// Which kinds of activity the merged lists are showing.
///
/// Those lists answer "what happened", but the two questions caregivers
/// actually ask — when did they last eat, when were they last changed — get
/// tangled together once a busy day has filled them.
///
/// Shared by Home's "Recent" list and the full Timeline. Home presents the
/// timeline as "see all" of the same data rather than a separate destination,
/// so a filter chosen in one carries into the other.
enum ActivityFilter {
  all('All', Icons.list),
  feeds('Feeds', Icons.local_drink),
  diapers('Diapers', Icons.baby_changing_station),
  pumps('Pumping', Icons.opacity);

  const ActivityFilter(this.label, this.icon);

  final String label;
  final IconData icon;

  bool matches(ActivityEntry entry) => switch (this) {
    ActivityFilter.all => true,
    ActivityFilter.feeds => entry is FeedingEntry,
    ActivityFilter.diapers => entry is DiaperEntry,
    ActivityFilter.pumps => entry is PumpingEntry,
  };
}

/// Keeps entries matching [filter], preserving order.
List<ActivityEntry> applyActivityFilter(
  List<ActivityEntry> entries,
  ActivityFilter filter,
) {
  if (filter == ActivityFilter.all) return entries;
  return entries.where(filter.matches).toList();
}

/// The selected filter. Deliberately in-memory rather than persisted: it's a
/// way of reading the current list, not a setting, and a filter silently still
/// applied days later would look like missing data.
final activityFilterProvider =
    NotifierProvider<ActivityFilterNotifier, ActivityFilter>(
      ActivityFilterNotifier.new,
    );

class ActivityFilterNotifier extends Notifier<ActivityFilter> {
  @override
  ActivityFilter build() => ActivityFilter.all;

  void select(ActivityFilter filter) => state = filter;
}

/// The chip row above the recent list.
class ActivityFilterBar extends ConsumerWidget {
  const ActivityFilterBar({super.key});

  /// How tall the bar is at [context]'s text size.
  ///
  /// Public because Home pins this bar, and a `SliverPersistentHeader` has to
  /// be given its extent before it lays anything out.
  static double barHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(44).clamp(44, 72);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(activityFilterProvider);

    // Grows with the reader's text size. It was a flat 44, which clipped the
    // chips once the labels scaled up — and it is now also the height a
    // pinned header has to be told in advance, so guessing it is no longer
    // only a cosmetic problem.
    return SizedBox(
      height: barHeight(context),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final filter in ActivityFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: selected == filter,
                label: Text(filter.label),
                avatar: Icon(filter.icon, size: 18),
                showCheckmark: false,
                // Re-tapping the active chip clears back to All, so there's
                // always a way out without hunting for the All chip.
                onSelected: (isOn) => ref
                    .read(activityFilterProvider.notifier)
                    .select(isOn ? filter : ActivityFilter.all),
              ),
            ),
        ],
      ),
    );
  }
}
