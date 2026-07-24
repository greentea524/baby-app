import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../common/event_tile.dart';
import '../diaper/diaper_format.dart';
import '../diaper/diaper_quick_log.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_quick_log.dart';

/// Unified recent activity: feeds and diaper changes merged by time. This is
/// the home dashboard's "what happened recently" view; the full daily
/// timeline with calendar + stats is KAN-132.
class RecentActivityList extends ConsumerWidget {
  const RecentActivityList({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedsAsync = ref.watch(recentFeedingsProvider);
    final diapersAsync = ref.watch(recentDiapersProvider);

    if (!feedsAsync.hasValue && feedsAsync.isLoading ||
        !diapersAsync.hasValue && diapersAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final tiles = <({DateTime time, Widget tile})>[
      for (final f in feedsAsync.value ?? const [])
        (
          time: f.startTime,
          tile: EventTile(
            key: ValueKey('feed_${f.id}'),
            icon: FeedingFormat.typeIcon(f.type),
            title: FeedingFormat.typeLabel(f.type),
            subtitle: FeedingFormat.details(f),
            trailing: FeedingFormat.timeAgo(f.startTime, now: now),
            confirmTitle: 'Delete feed?',
            deletedMessage: 'Feed deleted',
            onTap: () => showFeedingQuickLog(context, existing: f),
            onDelete: () async =>
                ref.read(feedingRepositoryProvider)?.delete(f.id),
          ),
        ),
      for (final d in diapersAsync.value ?? const [])
        (
          time: d.time,
          tile: EventTile(
            key: ValueKey('diaper_${d.id}'),
            icon: DiaperFormat.typeIcon(d.type),
            title: DiaperFormat.typeLabel(d.type),
            subtitle: DiaperFormat.details(d),
            trailing: FeedingFormat.timeAgo(d.time, now: now),
            confirmTitle: 'Delete diaper change?',
            deletedMessage: 'Diaper change deleted',
            onTap: () => showDiaperQuickLog(context, existing: d),
            onDelete: () async =>
                ref.read(diaperRepositoryProvider)?.delete(d.id),
          ),
        ),
    ]..sort((a, b) => b.time.compareTo(a.time));

    if (tiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No activity yet.'),
        ),
      );
    }

    return ListView.separated(
      itemCount: tiles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => tiles[i].tile,
    );
  }
}
