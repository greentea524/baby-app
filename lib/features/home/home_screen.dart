import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/launch_action.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/repository_providers.dart';
import '../activity/activity_filter.dart';
import '../caregivers/incoming_invites.dart';
import '../diaper/diaper_quick_log.dart';
import '../feeding/feeding_quick_log.dart';
import '../pumping/pumping_format.dart';
import '../pumping/pumping_quick_log.dart';
import 'add_baby_dialog.dart';
import 'baby_switcher.dart';
import 'home_prefs.dart';
import 'home_status_card.dart';
import 'recent_activity_list.dart';
import 'today_summary.dart';

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
                  HomeStatusCard(now: _now),
                  const TodaySummaryRow(),
                  const _QuickActions(),
                  const _RecentHeader(),
                  const ActivityFilterBar(),
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

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pumping is opt-in (KAN-181): it only applies to some caregivers, and
    // feeds and diapers are what most people open the app to log.
    final showPumping = ref.watch(showPumpingActionProvider);
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
          if (showPumping)
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
