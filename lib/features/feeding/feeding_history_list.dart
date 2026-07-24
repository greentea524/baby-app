import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/feeding_event.dart';
import '../../data/repositories/repository_providers.dart';
import 'feeding_format.dart';
import 'feeding_quick_log.dart';

/// Recent feedings with tap-to-edit and swipe-to-delete (KAN-147).
class FeedingHistoryList extends ConsumerWidget {
  const FeedingHistoryList({super.key, this.now});

  /// Injectable clock for deterministic "time ago" in tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedsAsync = ref.watch(recentFeedingsProvider);
    return feedsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load feeds: $e')),
      data: (feeds) {
        if (feeds.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No feeds logged yet.'),
            ),
          );
        }
        return ListView.separated(
          itemCount: feeds.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _FeedingTile(event: feeds[i], now: now),
        );
      },
    );
  }
}

class _FeedingTile extends ConsumerWidget {
  const _FeedingTile({required this.event, this.now});

  final FeedingEvent event;
  final DateTime? now;

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete feed?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = FeedingFormat.details(event);
    return Dismissible(
      key: ValueKey(event.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) async {
        await ref.read(feedingRepositoryProvider)?.delete(event.id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Feed deleted')));
        }
      },
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          Icons.delete,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      child: ListTile(
        leading: Icon(FeedingFormat.typeIcon(event.type)),
        title: Text(FeedingFormat.typeLabel(event.type)),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: Text(
          FeedingFormat.timeAgo(event.startTime, now: now),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () => showFeedingQuickLog(context, existing: event),
      ),
    );
  }
}
