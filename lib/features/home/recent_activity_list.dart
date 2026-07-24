import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/activity_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../activity/activity_tile.dart';

/// Unified recent activity: feeds and diaper changes merged by time. This is
/// the home dashboard's "what happened recently" view; the full daily
/// timeline with calendar + stats is the Timeline tab (KAN-132).
class RecentActivityList extends ConsumerWidget {
  const RecentActivityList({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedsAsync = ref.watch(recentFeedingsProvider);
    final diapersAsync = ref.watch(recentDiapersProvider);

    if ((!feedsAsync.hasValue && feedsAsync.isLoading) ||
        (!diapersAsync.hasValue && diapersAsync.isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }

    final entries = mergeActivities(
      feedsAsync.value ?? const [],
      diapersAsync.value ?? const [],
    );

    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No activity yet.'),
        ),
      );
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => ActivityTile(entry: entries[i], now: now),
    );
  }
}
