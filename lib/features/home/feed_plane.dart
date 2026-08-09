import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';
import 'home_prefs.dart';

/// What the plane is doing (#14).
enum PlaneState {
  /// The next feed is comfortably off.
  cruising,

  /// Inside the caregiver's heads-up window — coming in to land.
  approach,

  /// Due or overdue. On the ground, waiting to be refuelled.
  landed,

  /// A feed was just logged. One-shot, then back to cruising.
  takingOff,
}

/// Where the plane sits for [due], ignoring any take-off in progress.
PlaneState planeStateFor(FeedDueState due) => switch (due) {
  FeedDueState.upcoming => PlaneState.cruising,
  FeedDueState.soon => PlaneState.approach,
  FeedDueState.overdue => PlaneState.landed,
};

/// A small plane in the corner of Home that reads how close the next feed is,
/// and takes off when one is logged (#14).
///
/// Decorative on purpose: it is a second, glanceable read of what the
/// next-feed chip already says in words, and the chip stays the thing you
/// actually read. Not tappable — the quick-action feed button is a few
/// centimetres below, and a live control tucked in the app bar corner is one
/// you hit by accident rather than on purpose.
///
/// Drawn from Material's own flight icons rather than a hand-rolled path:
/// they are designed to stay legible at this size, they ship tree-shaken with
/// the icon font already in the build, and they keep the plane speaking the
/// same visual language as every other icon in the app. Colour is borrowed
/// from the chip's three states, so the two never disagree.
class FeedPlane extends ConsumerStatefulWidget {
  const FeedPlane({super.key, required this.now});

  final DateTime now;

  /// How long the take-off runs before handing back to the derived state.
  static const takeoffDuration = Duration(milliseconds: 1400);

  @override
  ConsumerState<FeedPlane> createState() => _FeedPlaneState();
}

class _FeedPlaneState extends ConsumerState<FeedPlane>
    with TickerProviderStateMixin {
  /// The slow drift while airborne. Deliberately long: this repaints for as
  /// long as Home is open, and a fast loop would be a battery cost paid for
  /// decoration.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  late final AnimationController _takeoff = AnimationController(
    vsync: this,
    duration: FeedPlane.takeoffDuration,
  );

  @override
  void initState() {
    super.initState();
    _takeoff.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _drift.dispose();
    _takeoff.dispose();
    super.dispose();
  }

  /// Runs the take-off once, from wherever it had got to.
  void _launch() {
    _takeoff
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    // A feed that drives the clock is the only thing that refuels the plane.
    // Snacks and solids do not move the due time, so triggering on those
    // would launch it and land it again inside the same second.
    ref.listen(lastClockFeedProvider, (previous, next) {
      // `previous == null` is the stream arriving, not a feed being logged —
      // otherwise every cold start would launch the plane.
      if (previous == null || next == null) return;
      if (previous.id != next.id) _launch();
    });

    if (!ref.watch(showFeedPlaneProvider)) return const SizedBox.shrink();

    final due = ref.watch(nextFeedDueProvider);
    // Reminders off: no due time, so there is no state to be in.
    if (due == null) return const SizedBox.shrink();

    final settings = ref.watch(reminderSettingsProvider);
    final resting = planeStateFor(
      feedDueState(due, now: widget.now, within: settings.headsUp),
    );

    // A stilled plane is still a plane: the pose keeps carrying the state,
    // it just does not move.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _drift.isAnimating) _drift.stop();
    if (!still && resting != PlaneState.landed && !_drift.isAnimating) {
      _drift.repeat();
    }
    if (still && resting == PlaneState.landed) _drift.stop();

    final flying = _takeoff.isAnimating;
    final state = flying ? PlaneState.takingOff : resting;

    return Semantics(
      label: _semantics(state),
      child: SizedBox(
        width: 48,
        height: kToolbarHeight,
        child: AnimatedBuilder(
          animation: Listenable.merge([_drift, _takeoff]),
          builder: (context, _) => CustomPaint(
            painter: _PlanePainter(
              state: _takeoff.isAnimating ? PlaneState.takingOff : resting,
              drift: still ? 0.35 : _drift.value,
              takeoff: still ? 0 : _takeoff.value,
              colors: _PlaneColors.of(context),
            ),
          ),
        ),
      ),
    );
  }

  String _semantics(PlaneState state) => switch (state) {
    PlaneState.cruising => 'Next feed is a while off',
    PlaneState.approach => 'Next feed is due soon',
    PlaneState.landed => 'Feed is due',
    PlaneState.takingOff => 'Feed logged',
  };
}

/// The plane borrows the next-feed chip's palette so the two always agree.
class _PlaneColors {
  const _PlaneColors({
    required this.cruising,
    required this.approach,
    required this.landed,
    required this.ground,
  });

  final Color cruising;
  final Color approach;
  final Color landed;
  final Color ground;

  factory _PlaneColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _PlaneColors(
      cruising: scheme.onSurfaceVariant,
      // The same amber the chip uses, for the same reason: no Material role
      // means "warning", so a seed-derived colour would stop reading as one.
      approach: theme.brightness == Brightness.dark
          ? const Color(0xFFFFC64D)
          : const Color(0xFF8A6600),
      landed: scheme.error,
      ground: scheme.outlineVariant,
    );
  }

  Color forState(PlaneState state) => switch (state) {
    PlaneState.cruising => cruising,
    PlaneState.approach => approach,
    PlaneState.landed => landed,
    PlaneState.takingOff => cruising,
  };
}

class _PlanePainter extends CustomPainter {
  _PlanePainter({
    required this.state,
    required this.drift,
    required this.takeoff,
    required this.colors,
  });

  final PlaneState state;

  /// 0..1 through the cruise loop.
  final double drift;

  /// 0..1 through the take-off.
  final double takeoff;

  final _PlaneColors colors;

  static const _iconSize = 22.0;

  IconData get _icon => switch (state) {
    PlaneState.cruising => Icons.flight,
    PlaneState.approach => Icons.flight_land,
    PlaneState.landed => Icons.flight_land,
    PlaneState.takingOff => Icons.flight_takeoff,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height * 0.72;

    // The runway only appears once the ground is part of the story — a line
    // under a cruising plane reads as an underline rather than as ground.
    if (state != PlaneState.cruising) {
      canvas.drawLine(
        Offset(4, groundY),
        Offset(size.width - 4, groundY),
        Paint()
          ..color = colors.ground
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    final (offset, angle, opacity) = _pose(size, groundY);
    _drawIcon(canvas, offset, angle, opacity);
  }

  /// Where the plane sits, how it is pitched, and how solid it is.
  (Offset, double, double) _pose(Size size, double groundY) {
    final centreX = size.width / 2;
    switch (state) {
      case PlaneState.cruising:
        // Crosses the slot and comes round again, riding a shallow bob so a
        // straight line does not read as a slide.
        //
        // Turned a quarter turn to face the way it is going: Icons.flight is
        // drawn from above, airport-signage style, while flight_land and
        // flight_takeoff are side views facing right. Left upright it would
        // be the one pose in the set looking somewhere else.
        final x = 6 + (size.width - 12) * drift;
        final bob = math.sin(drift * math.pi * 2) * 2;
        return (Offset(x, size.height * 0.42 + bob), math.pi / 2, 1);
      case PlaneState.approach:
        // Nose down, holding just above the runway.
        final bob = math.sin(drift * math.pi * 2) * 1.5;
        return (Offset(centreX, groundY - 12 + bob), 0, 1);
      case PlaneState.landed:
        return (Offset(centreX, groundY - 8), 0, 1);
      case PlaneState.takingOff:
        // Climbs away to the right and thins out, so the hand-off back to
        // cruising is a departure rather than a jump cut.
        final eased = Curves.easeOutCubic.transform(takeoff);
        return (
          Offset(centreX - 6 + 18 * eased, groundY - 8 - 22 * eased),
          -0.35 * eased,
          1 - math.max(0.0, (takeoff - 0.7) / 0.3),
        );
    }
  }

  void _drawIcon(Canvas canvas, Offset at, double angle, double opacity) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(_icon.codePoint),
        style: TextStyle(
          fontSize: _iconSize,
          fontFamily: _icon.fontFamily,
          package: _icon.fontPackage,
          color: colors.forState(state).withValues(alpha: opacity.clamp(0, 1)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (angle != 0) canvas.rotate(angle);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlanePainter old) =>
      old.state != state ||
      old.drift != drift ||
      old.takeoff != takeoff ||
      old.colors.cruising != colors.cruising;
}
