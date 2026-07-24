import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_history_list.dart';
import '../feeding/feeding_quick_log.dart';
import 'add_baby_dialog.dart';

/// Home dashboard: last-fed indicator (KAN-146), quick-log entry point,
/// and recent feed history.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Ticks so relative "time ago" labels stay fresh without a stream write.
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final babiesAsync = ref.watch(babiesStreamProvider);
    final baby = ref.watch(currentBabyProvider);

    return Scaffold(
      appBar: AppBar(title: Text(baby?.name ?? 'Home')),
      floatingActionButton: baby == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showFeedingQuickLog(context),
              icon: const Icon(Icons.add),
              label: const Text('Log feed'),
            ),
      body: babiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (_) => baby == null
            ? const _NoBabyPrompt()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LastFedCard(now: _now),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('Recent'),
                  ),
                  Expanded(child: FeedingHistoryList(now: _now)),
                ],
              ),
      ),
    );
  }
}

class _LastFedCard extends ConsumerWidget {
  const _LastFedCard({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastFeedingProvider);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                last == null
                    ? Icons.child_care
                    : FeedingFormat.typeIcon(last.type),
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last fed', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    last == null
                        ? 'No feeds yet'
                        : FeedingFormat.timeAgo(last.startTime, now: now),
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (last != null)
                    Text(
                      '${FeedingFormat.typeLabel(last.type)}'
                      '${FeedingFormat.details(last).isEmpty ? '' : ' · ${FeedingFormat.details(last)}'}',
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoBabyPrompt extends StatelessWidget {
  const _NoBabyPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.child_care,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Add your baby to start logging',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showAddBabyDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add baby'),
            ),
          ],
        ),
      ),
    );
  }
}
