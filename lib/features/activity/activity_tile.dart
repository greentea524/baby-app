import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/activity_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/event_tile.dart';
import '../diaper/diaper_format.dart';
import '../diaper/diaper_quick_log.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_quick_log.dart';

/// Renders one [ActivityEntry] (feed or diaper) as a swipe/tap [EventTile],
/// wiring edit and delete to the right repository. Shared by the home
/// recent list and the daily timeline.
class ActivityTile extends ConsumerWidget {
  const ActivityTile({
    super.key,
    required this.entry,
    this.now,
    this.clockTime = false,
  });

  final ActivityEntry entry;

  /// Injectable clock for deterministic "time ago" in tests.
  final DateTime? now;

  /// Show an absolute clock time (timeline) instead of relative "x ago".
  final bool clockTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trailing = clockTime
        ? TimeOfDay.fromDateTime(entry.time).format(context)
        : FeedingFormat.timeAgo(entry.time, now: now);

    return switch (entry) {
      FeedingEntry(:final event) => EventTile(
        key: ValueKey('feed_${event.id}'),
        icon: FeedingFormat.typeIcon(event.type),
        title: FeedingFormat.typeLabel(event.type),
        subtitle: FeedingFormat.details(event),
        trailing: trailing,
        confirmTitle: 'Delete feed?',
        deletedMessage: 'Feed deleted',
        onTap: () => showFeedingQuickLog(context, existing: event),
        onDelete: () async =>
            ref.read(feedingRepositoryProvider)?.delete(event.id),
      ),
      DiaperEntry(:final event) => EventTile(
        key: ValueKey('diaper_${event.id}'),
        icon: DiaperFormat.typeIcon(event.type),
        title: DiaperFormat.typeLabel(event.type),
        subtitle: DiaperFormat.details(event),
        trailing: trailing,
        confirmTitle: 'Delete diaper change?',
        deletedMessage: 'Diaper change deleted',
        onTap: () => showDiaperQuickLog(context, existing: event),
        onDelete: () async =>
            ref.read(diaperRepositoryProvider)?.delete(event.id),
      ),
    };
  }
}
