import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/launch_action.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/repository_providers.dart';
import '../activity/activity_filter.dart';
import '../appointments/next_appointment_button.dart';
import '../caregivers/incoming_invites.dart';
import '../diaper/diaper_quick_log.dart';
import '../feeding/feeding_quick_log.dart';
import '../pumping/pumping_format.dart';
import '../pumping/pumping_quick_log.dart';
import 'add_baby_dialog.dart';
import 'baby_switcher.dart';
import 'feed_companion.dart';
import 'home_access.dart';
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
    final actionsFirst = ref.watch(homeActionsProvider) == HomeActions.top;
    _maybeHandleLaunchAction(baby != null);

    return Scaffold(
      appBar: AppBar(
        // Decorative, so it takes the corner nothing else wanted rather than
        // a row from the things you can act on. Fits the default leading
        // width, which keeps the baby switcher's space unchanged.
        leading: baby == null ? null : FeedCompanion(now: _now),
        title: baby == null ? const Text('Home') : const BabySwitcher(),
        // The next visit lives in the corner rather than in the status card:
        // it is the one thing on Home you cannot act on today, so it wants to
        // be visible without taking a row from the things you can.
        actions: [if (baby != null) NextAppointmentButton(now: _now)],
      ),
      body: babiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (_) => baby == null
            ? ListView(children: const [IncomingInvitesBanner(), _EmptyHome()])
            // One scroll view for the whole screen. The status card and the
            // activity list used to be a fixed block above a list with its
            // own scroll area, so on a short screen — or at a large text
            // size — the cards held their full height and squeezed the list
            // into whatever was left. Now everything scrolls together and
            // nothing has to be given up.
            : CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: IncomingInvitesBanner()),
                  // Logging is what the app is opened for, so by default it
                  // is the first thing under the app bar rather than a third
                  // of the way down the screen.
                  if (actionsFirst)
                    const SliverToBoxAdapter(child: _QuickActions()),
                  SliverToBoxAdapter(child: HomeStatusCard(now: _now)),
                  const SliverToBoxAdapter(child: TodaySummaryRow()),
                  if (!actionsFirst)
                    const SliverToBoxAdapter(child: _QuickActions()),
                  const SliverToBoxAdapter(child: _RecentHeader()),
                  const SliverToBoxAdapter(child: ActivityFilterBar()),
                  RecentActivityList(now: _now),
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
    // A Wrap for the same reason as the status row: at 150% text the label
    // and the link no longer fit across a phone, and a Row overflowed. The
    // link drops to its own line instead of being clipped.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Recent'),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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

/// What Home shows before there is a baby to log against. Which of these is
/// right depends on who is signed in — see [homeEmptyState].
class _EmptyHome extends ConsumerWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = homeEmptyState(
      mayStartHousehold: ref.watch(mayStartHouseholdProvider),
      incomingInvites: ref.watch(incomingInvitesProvider),
    );
    return switch (state) {
      HomeEmptyState.loading => const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      ),
      HomeEmptyState.addBaby => const _NoBabyPrompt(),
      // The banner above this is the whole answer, so this only says so.
      HomeEmptyState.awaitingInvite => const _EmptyMessage(
        icon: Icons.mark_email_read_outlined,
        title: 'Accept the invitation above to start logging',
      ),
      HomeEmptyState.locked => const _LockedOutPrompt(),
    };
  }
}

class _NoBabyPrompt extends StatelessWidget {
  const _NoBabyPrompt();

  @override
  Widget build(BuildContext context) {
    return _EmptyMessage(
      icon: Icons.child_care,
      title: 'Add your baby to start logging',
      action: FilledButton.icon(
        onPressed: () => showAddBabyDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add baby'),
      ),
    );
  }
}

/// Shown to someone who signed in successfully but was never invited.
///
/// The address is on screen because that is the one thing they can act on:
/// an invitation goes to a specific Google account, and signing in with the
/// wrong one of your own accounts looks exactly like not being invited.
class _LockedOutPrompt extends ConsumerWidget {
  const _LockedOutPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = ref.watch(authStateProvider).value?.email;
    return _EmptyMessage(
      icon: Icons.lock_outline,
      title: 'Access is by invitation',
      body: Column(
        children: [
          if (email != null)
            Text(
              'You\'re signed in as $email, which hasn\'t been invited.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 8),
          Text(
            'If you were invited, check it went to this address — or sign '
            'in with the account it was sent to.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      action: OutlinedButton.icon(
        onPressed: () => ref.read(authRepositoryProvider).signOut(),
        icon: const Icon(Icons.logout),
        label: const Text('Use a different account'),
      ),
    );
  }
}

/// The shared shape of all three: icon, headline, optional detail, optional
/// action, centred in the empty body.
class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[const SizedBox(height: 12), body!],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
