import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../data/models/activity_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/event_tile.dart';
import '../diaper/diaper_format.dart';
import '../diaper/diaper_quick_log.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_quick_log.dart';
import '../pumping/pumping_format.dart';
import '../pumping/pumping_quick_log.dart';

/// How an [ActivityTile] labels when something happened.
enum ActivityTimeDisplay {
  /// "2 hr ago", with the absolute stamp underneath.
  relative,

  /// Just the clock time. For views already scoped to one day, where
  /// repeating the date on every row would be noise.
  clock,

  /// Clock time, prefixed with a short date when it isn't today. For lists
  /// that span days, where a bare "9:30 PM" is ambiguous.
  stamp,
}

/// Renders one [ActivityEntry] (feed or diaper) as a swipe/tap [EventTile],
/// wiring edit and delete to the right repository. Shared by the home
/// recent list and the daily timeline.
class ActivityTile extends ConsumerWidget {
  const ActivityTile({
    super.key,
    required this.entry,
    this.now,
    this.timeDisplay = ActivityTimeDisplay.relative,
  });

  final ActivityEntry entry;

  /// Injectable clock for deterministic times in tests.
  final DateTime? now;

  final ActivityTimeDisplay timeDisplay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitSystemProvider);

    final trailing = switch (timeDisplay) {
      ActivityTimeDisplay.relative => FeedingFormat.timeAgo(
        entry.time,
        now: now,
      ),
      ActivityTimeDisplay.clock => TimeOfDay.fromDateTime(
        entry.time,
      ).format(context),
      ActivityTimeDisplay.stamp => FeedingFormat.clockStamp(
        context,
        entry.time,
        now: now,
      ),
    };
    // Only the relative label needs a second line: "2 hr ago" is easy to scan
    // but you often want to know it was actually 9:30 AM. The absolute modes
    // already lead with that.
    final trailingDetail = timeDisplay == ActivityTimeDisplay.relative
        ? FeedingFormat.clockStamp(context, entry.time, now: now)
        : null;

    return switch (entry) {
      FeedingEntry(:final event) => EventTile(
        key: ValueKey('feed_${event.id}'),
        icon: FeedingFormat.typeIcon(event.type),
        title: FeedingFormat.eventLabel(event),
        subtitle: FeedingFormat.details(event, units),
        trailing: trailing,
        trailingDetail: trailingDetail,
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
        trailingDetail: trailingDetail,
        confirmTitle: 'Delete diaper change?',
        deletedMessage: 'Diaper change deleted',
        onTap: () => showDiaperQuickLog(context, existing: event),
        onDelete: () async =>
            ref.read(diaperRepositoryProvider)?.delete(event.id),
      ),
      PumpingEntry(:final event) => EventTile(
        key: ValueKey('pump_${event.id}'),
        icon: PumpingFormat.icon,
        title: PumpingFormat.label,
        subtitle: PumpingFormat.details(event, units),
        trailing: trailing,
        trailingDetail: trailingDetail,
        confirmTitle: 'Delete pumping?',
        deletedMessage: 'Pumping deleted',
        onTap: () => showPumpingQuickLog(context, existing: event),
        onDelete: () async =>
            ref.read(pumpingRepositoryProvider)?.delete(event.id),
      ),
    };
  }
}
