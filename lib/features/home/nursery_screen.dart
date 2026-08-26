import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/baby.dart';
import '../../data/models/feeding_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../diaper/diaper_quick_log.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_quick_log.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';
import 'baby_age.dart';
import 'home_prefs.dart';
import 'home_status_card.dart';

/// The app for a tablet propped on a shelf (#29).
///
/// Not Home scaled up — a different decision about how much belongs on
/// screen. Everything here can be read from across a room and tapped while
/// holding a baby, which means two readouts, three buttons, and nothing else:
/// no lists, no charts, no navigation bar.
///
/// The text is scaled inside this screen rather than app-wide, because the
/// screens that live in the full app want density. Insights charts and the
/// timeline list both read worse enlarged.
class NurseryScreen extends ConsumerWidget {
  const NurseryScreen({super.key, this.now});

  final DateTime? now;

  /// How much larger than usual this screen reads.
  static const textBoost = 1.35;

  /// The ceiling the boost is applied under.
  ///
  /// It multiplies with the reader's own accessibility setting, so someone
  /// already at 150% would land near 210% and lose the layout entirely. The
  /// boost is a floor to reach, not a factor to stack.
  static const maxTextScale = 1.6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = now ?? DateTime.now();
    final baby = ref.watch(currentBabyProvider);
    final scaler = MediaQuery.textScalerOf(context);

    // Whichever is larger, capped: a reader who has already asked for big
    // text keeps it, and nobody is scaled past what the layout survives.
    final boosted = TextScaler.linear(
      scaler.scale(1) < textBoost
          ? textBoost
          : (scaler.scale(1) > maxTextScale ? maxTextScale : scaler.scale(1)),
    );

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: boosted),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(baby: baby),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Readout(
                          label: 'Last fed',
                          event: ref.watch(lastMilkFeedProvider),
                          timeOf: (e) => e.startTime,
                          now: clock,
                        ),
                        const SizedBox(height: 16),
                        ?_nextFeed(context, ref, clock),
                        const SizedBox(height: 16),
                        _Readout(
                          label: 'Last changed',
                          event: ref.watch(lastDiaperProvider),
                          timeOf: (e) => e.time,
                          now: clock,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const _LogButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The one thing on this screen you can act on, so it stays.
  Widget? _nextFeed(BuildContext context, WidgetRef ref, DateTime clock) {
    final due = ref.watch(nextFeedDueProvider);
    if (due == null) return null;
    final at = TimeOfDay.fromDateTime(due).format(context);
    final state = feedDueState(
      due,
      now: clock,
      within: ref.watch(reminderSettingsProvider).headsUp,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: NextFeedChip(
        state: state,
        text: state == FeedDueState.overdue
            ? 'Feed ${countdownLabel(due, now: clock)} · due $at'
            : 'Next feed ${countdownLabel(due, now: clock)} · $at',
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.baby});

  final Baby? baby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                baby?.name ?? 'Baby App',
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (baby != null)
                Text(
                  babyAgeLabel(baby!.birthDate),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        // The only way out. The navigation bar is hidden in this mode, so
        // without this the device is stuck here and Settings is unreachable.
        IconButton(
          icon: const Icon(Icons.close_fullscreen),
          tooltip: 'Leave nursery mode',
          onPressed: () => ref
              .read(displayModeProvider.notifier)
              .setMode(DisplayMode.normal),
        ),
      ],
    );
  }
}

/// One large "how long ago" line.
class _Readout<T> extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.event,
    required this.timeOf,
    required this.now,
  });

  final String label;
  final T? event;
  final DateTime Function(T) timeOf;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = event;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        if (e == null)
          Text('Nothing logged yet', style: theme.textTheme.headlineSmall)
        else ...[
          // The elapsed time is the headline: at a glance across a room it is
          // the only number that matters.
          Text(
            FeedingFormat.timeAgo(timeOf(e), now: now),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            FeedingFormat.clockStamp(context, timeOf(e), now: now),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Bottle, breast, diaper — each straight into its sheet with the kind
/// already chosen, so there is no chooser step asking again.
class _LogButtons extends StatelessWidget {
  const _LogButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BigButton(
            icon: FeedingFormat.typeIcon(FeedingType.bottle),
            label: 'Bottle',
            onPressed: () =>
                showFeedingQuickLog(context, type: FeedingType.bottle),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BigButton(
            icon: FeedingFormat.typeIcon(FeedingType.breast),
            label: 'Breast',
            onPressed: () =>
                showFeedingQuickLog(context, type: FeedingType.breast),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BigButton(
            icon: Icons.baby_changing_station,
            label: 'Diaper',
            onPressed: () => showDiaperQuickLog(context),
          ),
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
