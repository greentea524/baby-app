import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/launch_action.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/repository_providers.dart';
import '../appointments/next_appointment_card.dart';
import '../caregivers/incoming_invites.dart';
import '../diaper/diaper_format.dart';
import '../diaper/diaper_quick_log.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_quick_log.dart';
import '../pumping/pumping_format.dart';
import '../pumping/pumping_quick_log.dart';
import '../reminders/next_feed_card.dart';
import 'add_baby_dialog.dart';
import 'baby_switcher.dart';
import 'recent_activity_list.dart';

/// Home dashboard: last-fed / last-changed indicators, quick-log entry
/// points for feeds (KAN-130) and diapers (KAN-131), and recent activity.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Ticks so relative "time ago" labels stay fresh without a stream write.
  Timer? _ticker;
  DateTime _now = DateTime.now();
  bool _launchHandled = false;

  /// Opens the quick-log sheet requested by a PWA shortcut (KAN-166), once
  /// a baby is available. Runs at most once per launch.
  void _maybeHandleLaunchAction(bool hasBaby) {
    if (_launchHandled || !hasBaby) return;
    final action = ref.read(launchActionProvider);
    if (action != 'feed' && action != 'diaper') return;
    _launchHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(launchActionProvider.notifier).consume();
      if (!mounted) return;
      if (action == 'feed') {
        showFeedingQuickLog(context);
      } else {
        showDiaperQuickLog(context);
      }
    });
  }

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
    _maybeHandleLaunchAction(baby != null);

    return Scaffold(
      appBar: AppBar(
        title: baby == null ? const Text('Home') : const BabySwitcher(),
      ),
      body: babiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (_) => baby == null
            ? ListView(
                children: const [IncomingInvitesBanner(), _NoBabyPrompt()],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const IncomingInvitesBanner(),
                  _SummaryCard(now: _now),
                  NextFeedCard(now: _now),
                  NextAppointmentCard(now: _now),
                  const _QuickActions(),
                  const _RecentHeader(),
                  Expanded(child: RecentActivityList(now: _now)),
                ],
              ),
      ),
    );
  }
}

/// "Recent" with the way through to the full daily timeline. The recent list
/// below is the short version of the same data, so this is a "see all" link
/// rather than a separate destination (KAN-175).
class _RecentHeader extends StatelessWidget {
  const _RecentHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          const Text('Recent'),
          const Spacer(),
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.timeline),
            icon: const Icon(Icons.timeline, size: 18),
            label: const Text('Full timeline'),
          ),
        ],
      ),
    );
  }
}

/// Compact card summarising the last feed and last diaper change.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastFeed = ref.watch(lastFeedingProvider);
    final lastDiaper = ref.watch(lastDiaperProvider);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _SummaryRow(
              icon: lastFeed == null
                  ? Icons.child_care
                  : FeedingFormat.typeIcon(lastFeed.type),
              label: 'Last fed',
              value: lastFeed == null
                  ? 'No feeds yet'
                  : FeedingFormat.timeAgo(lastFeed.startTime, now: now),
              detail: lastFeed == null
                  ? null
                  : _join(
                      FeedingFormat.clockStamp(
                        context,
                        lastFeed.startTime,
                        now: now,
                      ),
                      _join(
                        FeedingFormat.typeLabel(lastFeed.type),
                        FeedingFormat.details(lastFeed),
                      ),
                    ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _SummaryRow(
              icon: lastDiaper == null
                  ? Icons.baby_changing_station
                  : DiaperFormat.typeIcon(lastDiaper.type),
              label: 'Last changed',
              value: lastDiaper == null
                  ? 'No changes yet'
                  : FeedingFormat.timeAgo(lastDiaper.time, now: now),
              detail: lastDiaper == null
                  ? null
                  : _join(
                      FeedingFormat.clockStamp(
                        context,
                        lastDiaper.time,
                        now: now,
                      ),
                      _join(
                        DiaperFormat.typeLabel(lastDiaper.type),
                        DiaperFormat.details(lastDiaper),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _join(String label, String details) =>
      details.isEmpty ? label : '$label · $details';
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                Text(value, style: theme.textTheme.titleLarge),
                if (detail != null)
                  Text(detail!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => showFeedingQuickLog(context),
                  icon: const Icon(Icons.restaurant),
                  label: const Text('Log feed'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => showDiaperQuickLog(context),
                  icon: const Icon(Icons.baby_changing_station),
                  label: const Text('Log diaper'),
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: () => showPumpingQuickLog(context),
            icon: const Icon(PumpingFormat.icon, size: 18),
            label: const Text('Log pumping'),
          ),
        ],
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
