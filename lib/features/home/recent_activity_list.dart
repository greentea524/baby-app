import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/activity_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../activity/activity_filter.dart';
import '../activity/activity_tile.dart';
import '../timeline/timeline_format.dart';

/// How far back Home's recent list reaches.
///
/// Counted in whole days rather than hours so the list does not change under
/// the reader: at 72 hours, a feed logged at 4am drops off at 4am three days
/// later, which looks like data going missing. On calendar days everything
/// shifts once, at midnight.
const recentActivityDays = 3;

/// The oldest moment Home's recent list shows: midnight, two days before the
/// day [now] falls in, so the window is today plus the two days before it.
DateTime recentActivityCutoff(DateTime now) => DateTime(
  now.year,
  now.month,
  now.day,
).subtract(const Duration(days: recentActivityDays - 1));

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
    final medsAsync = ref.watch(recentMedsProvider);
    final checksAsync = ref.watch(recentChecksProvider);

    if ((!feedsAsync.hasValue && feedsAsync.isLoading) ||
        (!diapersAsync.hasValue && diapersAsync.isLoading) ||
        (!pumpsAsync.hasValue && pumpsAsync.isLoading) ||
        (!medsAsync.hasValue && medsAsync.isLoading) ||
        (!checksAsync.hasValue && checksAsync.isLoading)) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final all = mergeActivities(
      feedsAsync.value ?? const [],
      diapersAsync.value ?? const [],
      pumps: pumpsAsync.value ?? const [],
      meds: medsAsync.value ?? const [],
      checks: checksAsync.value ?? const [],
    );

    if (all.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No activity yet.')),
        ),
      );
    }

    // "Recent" now means a window rather than a count. The list was the last
    // 50 of each kind merged, which on a busy week ran to hundreds of rows —
    // a scroll nobody reaches the end of, when the question it answers is
    // what has been happening lately. Anything older is a day to look up on
    // the timeline, not a row to scroll past.
    final cutoff = recentActivityCutoff(now ?? DateTime.now());
    final entries = all.where((e) => !e.time.isBefore(cutoff)).toList();

    if (entries.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Nothing logged in the last $recentActivityDays days.'),
          ),
        ),
      );
    }

    final filter = ref.watch(activityFilterProvider);
    final visible = applyActivityFilter(entries, filter);

    // Distinct from a quiet three days: there *is* activity in the window,
    // just none of this kind, and saying so points at the filter as reason.
    if (visible.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No ${filter.label.toLowerCase()} in the last '
              '$recentActivityDays days.',
            ),
          ),
        ),
      );
    }

    // Under a heading for each day — "Today", "Yesterday", "Wed, Nov 11" —
    // so each row needs only its clock time. Every row older than today
    // used to carry its own date, so the list mixed "1:44 AM" with "Nov 12,
    // 11:29 PM" and midnight was something to work out rather than see.
    final rows = <Object>[];
    DateTime? day;
    for (final e in visible) {
      final d = DateTime(e.time.year, e.time.month, e.time.day);
      if (d != day) {
        rows.add(d);
        day = d;
      }
      rows.add(e);
    }
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) => switch (rows[i]) {
        final DateTime d => _DayHeading(day: d, now: now),
        final e as ActivityEntry => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ActivityTile(
              entry: e,
              now: now,
              timeDisplay: ActivityTimeDisplay.clock,
            ),
            // Between rows of one day; the next heading separates days.
            if (i + 1 < rows.length && rows[i + 1] is ActivityEntry)
              const Divider(height: 1),
          ],
        ),
      },
    );
  }
}

/// A day's heading in the list, as the fridge's history has them.
class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.day, this.now});

  final DateTime day;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          TimelineFormat.dayLabel(day, now: now),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
