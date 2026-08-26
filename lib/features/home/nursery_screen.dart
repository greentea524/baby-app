import 'dart:async';

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
import '../timeline/timeline_format.dart';
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
class NurseryScreen extends ConsumerStatefulWidget {
  const NurseryScreen({super.key, this.now});

  /// A fixed clock, for tests. When given, the screen does not tick — a live
  /// timer in a widget test is a pending-timer failure at teardown.
  final DateTime? now;

  /// How much larger than usual this screen reads.
  static const textBoost = 1.35;

  /// The ceiling the boost is applied under.
  ///
  /// It multiplies with the reader's own accessibility setting, so someone
  /// already at 150% would land near 210% and lose the layout entirely. The
  /// boost is a floor to reach, not a factor to stack.
  static const maxTextScale = 1.6;

  /// How often the screen catches up with the clock.
  ///
  /// This mode is left running on a shelf, so nothing else ever rebuilds it.
  /// Without a tick the elapsed times froze at whatever they said when the
  /// mode was entered — on the one screen whose whole content is how long it
  /// has been. Short enough that the displayed minute is never far wrong.
  static const tick = Duration(seconds: 15);

  @override
  ConsumerState<NurseryScreen> createState() => _NurseryScreenState();
}

class _NurseryScreenState extends ConsumerState<NurseryScreen> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.now != null) return;
    _ticker = Timer.periodic(
      NurseryScreen.tick,
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
    final clock = widget.now ?? _now;
    final baby = ref.watch(currentBabyProvider);
    final scaler = MediaQuery.textScalerOf(context);

    // Whichever is larger, capped: a reader who has already asked for big
    // text keeps it, and nobody is scaled past what the layout survives.
    final boosted = TextScaler.linear(
      scaler.scale(1) < NurseryScreen.textBoost
          ? NurseryScreen.textBoost
          : (scaler.scale(1) > NurseryScreen.maxTextScale
                ? NurseryScreen.maxTextScale
                : scaler.scale(1)),
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
                _Header(baby: baby, clock: clock),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fed = _Readout(
                        icon: Icons.local_drink_outlined,
                        label: 'Last fed',
                        event: ref.watch(lastMilkFeedProvider),
                        timeOf: (e) => e.startTime,
                        now: clock,
                      );
                      final changed = _Readout(
                        icon: Icons.baby_changing_station,
                        label: 'Last changed',
                        event: ref.watch(lastDiaperProvider),
                        timeOf: (e) => e.time,
                        now: clock,
                      );

                      // Side by side when the space is wider than it is
                      // tall. The buttons stay along the bottom either way,
                      // so in landscape the cards get the whole width rather
                      // than half of it, which is the room they needed.
                      final cards = _twoAcross(constraints)
                          // IntrinsicHeight so the pair matches the taller of
                          // them. Stretching instead asks for infinite height
                          // inside the scroll view below, which is an
                          // assertion rather than a layout.
                          ? IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: fed),
                                  const SizedBox(width: 16),
                                  Expanded(child: changed),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                fed,
                                const SizedBox(height: 16),
                                changed,
                              ],
                            );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            // Centred in whatever is left, and scrollable if
                            // that is not enough. With the buttons pinned to
                            // the bottom, top-aligned cards leave a hole in
                            // the middle of a landscape screen — which is the
                            // shape this mode is most often seen in.
                            child: LayoutBuilder(
                              builder: (context, space) => SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: space.maxHeight,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      cards,
                                      const SizedBox(height: 16),
                                      ?_nextFeed(context, ref, clock),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const _LogButtons(),
                        ],
                      );
                    },
                  ),
                ),
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
  const _Header({required this.baby, required this.clock});

  final Baby? baby;
  final DateTime clock;

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
        // A tablet on a nursery shelf is the nearest clock at 3am, and the
        // screen has to tick anyway to keep the elapsed times honest — so
        // this costs two lines and answers the other question being asked.
        //
        // Centred on the screen, not merely placed between its neighbours:
        // the two sides are equal-flex Expandeds, so whatever space is left
        // after this block is split evenly and it lands in the middle. The
        // name gives way first, which is the right one to lose.
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TimeOfDay.fromDateTime(clock).format(context),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
            ),
            Text(
              // Never "Today", which a clock has no use for.
              TimelineFormat.weekdayDate(clock),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
            ),
          ],
        ),
        // The only way out. The navigation bar is hidden in this mode, so
        // without this the device is stuck here and Settings is unreachable.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close_fullscreen),
              tooltip: 'Leave nursery mode',
              onPressed: () => ref
                  .read(displayModeProvider.notifier)
                  .setMode(DisplayMode.normal),
            ),
          ),
        ),
      ],
    );
  }
}

/// One "how long ago" card.
///
/// A card rather than bare text: on a screen with only two readings on it,
/// each needs an edge of its own or the pair reads as one paragraph. The
/// icon carries which is which at a glance, so the label does not have to be
/// read from across the room to tell them apart.
class _Readout<T> extends StatelessWidget {
  const _Readout({
    required this.icon,
    required this.label,
    required this.event,
    required this.timeOf,
    required this.now,
  });

  final IconData icon;
  final String label;
  final T? event;
  final DateTime Function(T) timeOf;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = event;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (e == null)
                  Text(
                    'Nothing logged yet',
                    style: theme.textTheme.titleLarge,
                  )
                else ...[
                  // The elapsed time is the headline: from across a room it
                  // is the only number that matters.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      FeedingFormat.timeAgo(timeOf(e), now: now),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  Text(
                    FeedingFormat.clockStamp(context, timeOf(e), now: now),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether the two cards should sit beside each other rather than stacked.
///
/// Wider than tall, with enough width for each to be worth having. Measured
/// on the *available* width, after the nursery cap, so it does not depend on
/// the size of the screen behind it.
bool _twoAcross(BoxConstraints c) =>
    c.maxWidth > c.maxHeight && c.maxWidth >= 620;

/// Bottle and diaper — each straight into its sheet with the kind already
/// chosen, so there is no chooser step asking again.
///
/// Two, not three. Breast was here and is not any more: anything this screen
/// does not carry is still a tap away through the full app, and two buttons
/// across a nursery screen are bigger targets than three.
class _LogButtons extends StatelessWidget {
  const _LogButtons();

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _BigButton(
        icon: FeedingFormat.typeIcon(FeedingType.bottle),
        label: 'Bottle',
        onPressed: () => showFeedingQuickLog(context, type: FeedingType.bottle),
      ),
      _BigButton(
        icon: Icons.baby_changing_station,
        label: 'Diaper',
        onPressed: () => showDiaperQuickLog(context),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: buttons[i]),
        ],
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
    // Size and weight only, with no colour of its own.
    //
    // Passing `textTheme.titleMedium` here carried the theme's colour with
    // it — a near-black `onSurface` — which overrode the button's own
    // foreground and put black text on a filled blue button. Leaving colour
    // null lets it inherit from the button, which is right in both themes and
    // stays right if the button's colours ever change.
    final text = Flexible(
      child: Text(
        label,
        style: TextStyle(
          fontSize: Theme.of(context).textTheme.titleMedium?.fontSize,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30),
          const SizedBox(height: 6),
          text,
        ],
      ),
    );
  }
}
