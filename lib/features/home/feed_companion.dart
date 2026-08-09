import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';
import 'companion_art.dart';
import 'home_prefs.dart';

/// A small companion in the corner of Home that reads how close the next feed
/// is, and celebrates when one is logged (#14, #16).
///
/// Decorative on purpose: a second, glanceable read of what the next-feed chip
/// already says in words, and the chip stays the thing you actually read. Not
/// tappable — the quick-action feed button is a few centimetres below, and a
/// live control tucked in the app bar corner is one you hit by accident rather
/// than on purpose.
///
/// Which companion is drawn is the caregiver's choice; everything here is the
/// part that does not care. See [CompanionArt] for the styles themselves.
class FeedCompanion extends ConsumerStatefulWidget {
  const FeedCompanion({super.key, required this.now});

  final DateTime now;

  /// How long the celebration runs before handing back to the resting phase.
  static const celebrateDuration = Duration(milliseconds: 1400);

  @override
  ConsumerState<FeedCompanion> createState() => _FeedCompanionState();
}

class _FeedCompanionState extends ConsumerState<FeedCompanion>
    with TickerProviderStateMixin {
  /// The idle loop. Deliberately long: it repaints for as long as Home is
  /// open, and a fast loop is battery spent on decoration.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  late final AnimationController _celebrate = AnimationController(
    vsync: this,
    duration: FeedCompanion.celebrateDuration,
  );

  @override
  void initState() {
    super.initState();
    _celebrate.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _drift.dispose();
    _celebrate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A feed that drives the clock is the only thing that resets the
    // companion. Snacks and solids do not move the due time, so triggering on
    // those would celebrate and un-celebrate inside the same second.
    ref.listen(lastClockFeedProvider, (previous, next) {
      // `previous == null` is the stream arriving, not a feed being logged —
      // otherwise every cold start would celebrate.
      if (previous == null || next == null) return;
      if (previous.id != next.id) {
        _celebrate
          ..reset()
          ..forward();
      }
    });

    final art = ref.watch(companionStyleProvider).art;
    if (art == null) return const SizedBox.shrink();

    final due = ref.watch(nextFeedDueProvider);
    // Reminders off: no due time, so there is no phase to be in.
    if (due == null) return const SizedBox.shrink();

    final settings = ref.watch(reminderSettingsProvider);
    final resting = phaseFor(
      feedDueState(due, now: widget.now, within: settings.headsUp),
    );
    final phase = _celebrate.isAnimating ? CompanionPhase.justFed : resting;

    // Stilled, the companion still carries its phase — it just does not move.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shouldIdle = !still && art.idles(resting) && !_celebrate.isAnimating;
    if (shouldIdle && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!shouldIdle && _drift.isAnimating) {
      _drift.stop();
    }

    return Semantics(
      label: _semantics(phase),
      child: SizedBox(
        width: 48,
        height: kToolbarHeight,
        child: AnimatedBuilder(
          animation: Listenable.merge([_drift, _celebrate]),
          builder: (context, _) => CustomPaint(
            painter: _CompanionPainter(
              art: art,
              phase: _celebrate.isAnimating
                  ? CompanionPhase.justFed
                  : resting,
              drift: still ? 0.35 : _drift.value,
              celebrate: still ? 0 : _celebrate.value,
              colors: CompanionColors.of(context),
            ),
          ),
        ),
      ),
    );
  }

  /// Shared across styles on purpose: a screen reader wants the state, not
  /// the metaphor.
  String _semantics(CompanionPhase phase) => switch (phase) {
    CompanionPhase.easy => 'Next feed is a while off',
    CompanionPhase.soon => 'Next feed is due soon',
    CompanionPhase.due => 'Feed is due',
    CompanionPhase.justFed => 'Feed logged',
  };
}

/// The companion borrows the next-feed chip's palette so the two always agree.
class CompanionColors {
  const CompanionColors({
    required this.easy,
    required this.soon,
    required this.due,
    required this.ground,
  });

  final Color easy;
  final Color soon;
  final Color due;
  final Color ground;

  factory CompanionColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CompanionColors(
      easy: scheme.onSurfaceVariant,
      // The same amber the chip uses, for the same reason: no Material role
      // means "warning", so a seed-derived colour would stop reading as one.
      soon: theme.brightness == Brightness.dark
          ? const Color(0xFFFFC64D)
          : const Color(0xFF8A6600),
      due: scheme.error,
      ground: scheme.outlineVariant,
    );
  }

  Color forPhase(CompanionPhase phase) => switch (phase) {
    CompanionPhase.easy => easy,
    CompanionPhase.soon => soon,
    CompanionPhase.due => due,
    CompanionPhase.justFed => easy,
  };
}

class _CompanionPainter extends CustomPainter {
  _CompanionPainter({
    required this.art,
    required this.phase,
    required this.drift,
    required this.celebrate,
    required this.colors,
  });

  final CompanionArt art;
  final CompanionPhase phase;
  final double drift;
  final double celebrate;
  final CompanionColors colors;

  static const _iconSize = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (art.ground(phase)) {
      final y = size.height * 0.72;
      canvas.drawLine(
        Offset(4, y),
        Offset(size.width - 4, y),
        Paint()
          ..color = colors.ground
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    final pose = art.pose(
      phase,
      size,
      drift: drift,
      celebrate: celebrate,
    );
    final icon = art.icon(phase);

    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: _iconSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: colors
              .forPhase(phase)
              .withValues(alpha: pose.opacity.clamp(0, 1)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(pose.at.dx, pose.at.dy);
    if (pose.angle != 0) canvas.rotate(pose.angle);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompanionPainter old) =>
      old.art.runtimeType != art.runtimeType ||
      old.phase != phase ||
      old.drift != drift ||
      old.celebrate != celebrate ||
      old.colors.easy != colors.easy;
}
