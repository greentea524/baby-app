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
import '../insights/day_timeline_strip.dart';
import '../insights/day_view_data.dart';
import '../insights/diaper_mix_bar.dart';
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
    final showList =
        ref.watch(homeActivityScopeProvider) == HomeActivityScope.recent;
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
                  // The day charts' legend carries the counts, so the row
                  // above them is left with the volumes it alone can show.
                  SliverToBoxAdapter(
                    child: TodaySummaryRow(showCounts: showList),
                  ),
                  if (!actionsFirst)
                    const SliverToBoxAdapter(child: _QuickActions()),
                  // Today is the same day the Insights day view draws, shown
                  // here so the glance does not cost a tab change. Recent is
                  // the running log, which needs its kind filter; the charts
                  // do not, so the bar is only there for the list.
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedActivityControls(
                      extent:
                          _RecentHeader.headerHeight(context) +
                          (showList ? ActivityFilterBar.barHeight(context) : 0),
                      showFilters: showList,
                      background: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  if (showList)
                    RecentActivityList(now: _now)
                  else
                    SliverToBoxAdapter(child: _TodayCharts(now: _now)),
                ],
              ),
      ),
    );
  }
}

/// The activity list's scope, with the way through to the full daily
/// timeline. The list below is the short version of the same data, so this is
/// a "see all" link rather than a separate destination (KAN-175).
///
/// Deliberately a single line at every text size. It is pinned to the top of
/// the list, and a pinned header has to be told its height before it lays
/// anything out — a row that might wrap to two lines cannot be measured in
/// advance, and guessing short would clip it. That is why the timeline link
/// is an icon here rather than the labelled button it used to be.
class _RecentHeader extends ConsumerWidget {
  const _RecentHeader();

  /// How tall the header is at [context]'s text size.
  ///
  /// Floors at 48 because an [IconButton] is 48 high whatever the text size,
  /// and the first attempt sized this from the text alone — which came out
  /// exactly 8 pixels short and overflowed at every scale.
  static double headerHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(40).clamp(48, 88) + 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(homeActivityScopeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          // Replaces a plain "Recent" heading: the word was already there
          // saying what the list held, so making it the control costs no
          // room and one tap now changes what the list holds.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<HomeActivityScope>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity(horizontal: -2, vertical: -2),
                ),
                showSelectedIcon: false,
                segments: [
                  for (final s in HomeActivityScope.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {scope},
                onSelectionChanged: (s) => ref
                    .read(homeActivityScopeProvider.notifier)
                    .setScope(s.first),
              ),
            ),
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.timeline),
            icon: const Icon(Icons.timeline),
            tooltip: 'Full timeline',
          ),
        ],
      ),
    );
  }
}

/// Keeps the scope toggle and the kind filters on screen while the rows
/// scroll under them.
///
/// Home is one scroll view, so without this the controls for the list
/// disappear as soon as you start reading it — which is exactly when you
/// want to change what it is showing.
class _PinnedActivityControls extends SliverPersistentHeaderDelegate {
  const _PinnedActivityControls({
    required this.extent,
    required this.showFilters,
    required this.background,
  });

  final double extent;
  final bool showFilters;
  final Color background;

  @override
  double get maxExtent => extent;

  @override
  double get minExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      // Sized to exactly [extent], not merely no taller than it. A pinned
      // header whose child comes out shorter than its declared extent fails
      // the sliver's own geometry check — "layoutExtent exceeds
      // paintExtent" — so the header takes the height it claimed and the
      // toggle row absorbs whatever the filter bar does not.
      SizedBox(
        height: extent,
        // Opaque, or the rows would scroll visibly behind the controls.
        child: ColoredBox(
          color: background,
          child: Column(
            children: [
              const Expanded(child: _RecentHeader()),
              if (showFilters) const ActivityFilterBar(),
            ],
          ),
        ),
      );

  @override
  bool shouldRebuild(_PinnedActivityControls old) =>
      old.extent != extent ||
      old.showFilters != showFilters ||
      old.background != background;
}

/// Today at a glance: the same two charts the Insights day view draws.
///
/// Built from the recent streams Home already subscribes to rather than the
/// range query behind Insights — they hold the last fifty of each, which
/// covers a day comfortably, and it means the charts move the instant
/// something is logged instead of on a refetch.
class _TodayCharts extends ConsumerWidget {
  const _TodayCharts({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayEventsProvider);
    // Not limited to today: "none yet" means something different at six in
    // the morning than at six in the evening, and what separates them is
    // when the last one actually was.
    final recentDiapers = ref.watch(recentDiapersProvider).value ?? const [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DayTimelineStrip(
            marks: dayMarks(
              day: now,
              feedings: today.feedings,
              diapers: today.diapers,
              pumps: today.pumps,
            ),
          ),
          const SizedBox(height: 20),
          DiaperMixBar(
            mix: diaperMix(today.diapers),
            lastWithPoop: lastWithPoop(recentDiapers),
            now: now,
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
