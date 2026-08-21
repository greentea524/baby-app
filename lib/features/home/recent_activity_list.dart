import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/activity_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../activity/activity_filter.dart';
import '../activity/activity_tile.dart';
import 'home_prefs.dart';

/// Unified recent activity: feeds and diaper changes merged by time. This is
/// the home dashboard's "what happened recently" view; the full daily
/// timeline with calendar + stats is the Timeline tab (KAN-132).
///
/// A sliver rather than a widget, because Home is one scroll view now: the
/// list used to have a scroll area of its own inside an `Expanded`, which
/// pinned it to whatever height was left over and meant the cards above it
/// could never move out of the way on a short screen.
class RecentActivityList extends ConsumerWidget {
  const RecentActivityList({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedsAsync = ref.watch(recentFeedingsProvider);
    final diapersAsync = ref.watch(recentDiapersProvider);
    final pumpsAsync = ref.watch(recentPumpingProvider);

    if ((!feedsAsync.hasValue && feedsAsync.isLoading) ||
        (!diapersAsync.hasValue && diapersAsync.isLoading) ||
        (!pumpsAsync.hasValue && pumpsAsync.isLoading)) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final entries = mergeActivities(
      feedsAsync.value ?? const [],
      diapersAsync.value ?? const [],
      pumps: pumpsAsync.value ?? const [],
    );

    if (entries.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No activity yet.')),
        ),
      );
    }

    final scope = ref.watch(homeActivityScopeProvider);
    final inScope = scope == HomeActivityScope.today
        ? onlyToday(entries, now: now ?? DateTime.now())
        : entries;

    // Distinct from an empty filter result: the day has not started, rather
    // than the filter having hidden everything.
    if (inScope.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Nothing logged today yet.')),
        ),
      );
    }

    final filter = ref.watch(activityFilterProvider);
    final visible = applyActivityFilter(inScope, filter);

    // Distinct from "No activity yet": there *is* activity, just none of this
    // kind, and saying so points at the filter as the reason.
    if (visible.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              scope == HomeActivityScope.today
                  ? 'No ${filter.label.toLowerCase()} today.'
                  : 'No ${filter.label.toLowerCase()} in recent activity.',
            ),
          ),
        ),
      );
    }

    return SliverList.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => ActivityTile(
        entry: visible[i],
        now: now,
        // A timestamp rather than "2 hr ago". Recent spans days, so the
        // stamp carries a short date once a row is older than today —
        // a bare "9:30 PM" could otherwise be any night. In Today every row
        // is today by definition, and the date would be noise on all of them.
        timeDisplay: ActivityTimeDisplay.stamp,
      ),
    );
  }
}

/// Entries from the same calendar day as [now], newest first.
///
/// A calendar day, not the last 24 hours: "today" on a dashboard means since
/// midnight, and a rolling window would keep last night's 11pm feed on the
/// list well into this afternoon.
List<ActivityEntry> onlyToday(
  List<ActivityEntry> entries, {
  required DateTime now,
}) {
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));
  return [
    for (final e in entries)
      if (!e.time.isBefore(start) && e.time.isBefore(end)) e,
  ];
}
