import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../reminders/feed_prediction.dart';

/// Which companion Home flies in the app bar corner (#16).
///
/// A picker rather than a switch plus a picker: "none" is a choice about the
/// same thing as "which one", so it belongs in the same control.
enum CompanionStyle {
  off('Off', 'Nothing in the corner'),
  plane('Plane', 'Lands when a feed is due, takes off when you log one'),
  bottle('Bottle', 'Empties toward the feed, refills when you log one'),
  hourglass('Hourglass', 'Runs out toward the feed, flips when you log one'),
  battery('Battery', 'Drains toward the feed, charges when you log one');

  const CompanionStyle(this.label, this.description);

  final String label;
  final String description;

  static CompanionStyle fromName(String? name) =>
      values.asNameMap()[name] ?? plane;

  /// How the companion is drawn, or null for [off].
  CompanionArt? get art => switch (this) {
    CompanionStyle.off => null,
    CompanionStyle.plane => const PlaneArt(),
    CompanionStyle.bottle => const BottleArt(),
    CompanionStyle.hourglass => const HourglassArt(),
    CompanionStyle.battery => const BatteryArt(),
  };
}

/// What the companion is doing.
enum CompanionPhase {
  /// The next feed is comfortably off.
  easy,

  /// Inside the caregiver's heads-up window.
  soon,

  /// Due, or past it.
  due,

  /// A feed was just logged. One-shot, then back to [easy].
  justFed,
}

/// Where the companion sits for [due], ignoring any celebration in progress.
CompanionPhase phaseFor(FeedDueState due) => switch (due) {
  FeedDueState.upcoming => CompanionPhase.easy,
  FeedDueState.soon => CompanionPhase.soon,
  FeedDueState.overdue => CompanionPhase.due,
};

/// How a companion is posed and drawn.
///
/// Everything around this — deciding the phase, spotting a newly logged feed,
/// the controllers, reduced motion, the semantics — is shared, so a new style
/// is an icon per phase and a little arithmetic, not a new feature.
abstract class CompanionArt {
  const CompanionArt();

  /// The glyph for [phase].
  IconData icon(CompanionPhase phase);

  /// Where it sits, how far it is rotated, and how solid it is.
  ///
  /// [drift] runs 0..1 through the idle loop, [celebrate] 0..1 through the
  /// one-shot after a feed.
  CompanionPose pose(
    CompanionPhase phase,
    Size size, {
    required double drift,
    required double celebrate,
  });

  /// How full to draw the glyph, 0..1 from the bottom, or null to draw it
  /// whole.
  ///
  /// [progress] runs 0 at the last feed to 1 at the next one due. Styles that
  /// use it turn the countdown into something continuous — "about half way"
  /// rather than "not amber yet" — which is more than the three phases can
  /// say on their own.
  double? level(
    CompanionPhase phase, {
    required double progress,
    required double celebrate,
  }) => null;

  /// Whether to rule a line under the companion for [phase].
  bool ground(CompanionPhase phase) => false;

  /// Whether the idle loop needs to run at all for [phase]. A style that
  /// holds still can stop the controller and stop repainting.
  bool idles(CompanionPhase phase) => false;
}

typedef CompanionPose = ({Offset at, double angle, double opacity});

CompanionPose _pose(Offset at, {double angle = 0, double opacity = 1}) =>
    (at: at, angle: angle, opacity: opacity);

/// A plane that cruises, comes in to land, waits on the ground, and takes off
/// again when a feed is logged (#14).
class PlaneArt extends CompanionArt {
  const PlaneArt();

  @override
  IconData icon(CompanionPhase phase) => switch (phase) {
    CompanionPhase.easy => Icons.flight,
    CompanionPhase.soon => Icons.flight_land,
    CompanionPhase.due => Icons.flight_land,
    CompanionPhase.justFed => Icons.flight_takeoff,
  };

  // A line under a cruising plane reads as an underline rather than as
  // ground, so the runway only appears once the ground is part of the story.
  @override
  bool ground(CompanionPhase phase) => phase != CompanionPhase.easy;

  @override
  bool idles(CompanionPhase phase) => phase != CompanionPhase.due;

  @override
  CompanionPose pose(
    CompanionPhase phase,
    Size size, {
    required double drift,
    required double celebrate,
  }) {
    final groundY = size.height * 0.72;
    final centreX = size.width / 2;
    switch (phase) {
      case CompanionPhase.easy:
        // Crosses the slot and comes round again, riding a shallow bob so a
        // straight line does not read as a slide.
        //
        // Turned a quarter turn to face the way it is going: Icons.flight is
        // drawn from above, airport-signage style, while flight_land and
        // flight_takeoff are side views facing right. Left upright it would
        // be the one pose in the set looking somewhere else.
        return _pose(
          Offset(
            6 + (size.width - 12) * drift,
            size.height * 0.42 + math.sin(drift * math.pi * 2) * 2,
          ),
          angle: math.pi / 2,
        );
      case CompanionPhase.soon:
        return _pose(
          Offset(centreX, groundY - 12 + math.sin(drift * math.pi * 2) * 1.5),
        );
      case CompanionPhase.due:
        return _pose(Offset(centreX, groundY - 8));
      case CompanionPhase.justFed:
        // Climbs away to the right and thins out, so the hand-off back to
        // cruising is a departure rather than a jump cut.
        final eased = Curves.easeOutCubic.transform(celebrate);
        // Clamped rather than trusted: (1 - 0.7) / 0.3 comes out a hair over
        // 1 in binary, so the fade would end fractionally below zero and
        // break the 0..1 the pose promises.
        final fade = ((celebrate - 0.7) / 0.3).clamp(0.0, 1.0);
        return _pose(
          Offset(centreX - 6 + 18 * eased, groundY - 8 - 22 * eased),
          angle: -0.35 * eased,
          opacity: 1 - fade,
        );
    }
  }
}

/// A bottle that empties toward the next feed and refills when one is logged
/// (#17).
///
/// The app already draws `Icons.local_drink` for a bottle feed, so this is
/// its own icon rather than a borrowed one.
///
/// The only style whose reading is continuous: the other three strike three
/// poses, but the level renders where `now` actually sits between the last
/// feed and the next, so a glance answers "about half way" rather than only
/// "not amber yet".
class BottleArt extends CompanionArt {
  const BottleArt();

  @override
  IconData icon(CompanionPhase phase) => Icons.local_drink;

  @override
  CompanionPose pose(
    CompanionPhase phase,
    Size size, {
    required double drift,
    required double celebrate,
  }) => _pose(Offset(size.width / 2, size.height / 2));

  @override
  double? level(
    CompanionPhase phase, {
    required double progress,
    required double celebrate,
  }) {
    // Pouring back to full. Eased out so it slows as it fills, the way a
    // bottle does, rather than slamming to the top.
    if (phase == CompanionPhase.justFed) {
      return Curves.easeOut.transform(celebrate);
    }
    // Full just after a feed, empty by the time the next one is due.
    return (1 - progress).clamp(0.0, 1.0);
  }
}

/// Sand running out toward the next feed, flipped over when one is logged
/// (#18).
///
/// The cheapest style in the set: three stock icons and a rotation, with no
/// drawing of its own and nothing looping between feeds.
class HourglassArt extends CompanionArt {
  const HourglassArt();

  @override
  IconData icon(CompanionPhase phase) => switch (phase) {
    CompanionPhase.easy => Icons.hourglass_top,
    CompanionPhase.soon => Icons.hourglass_bottom,
    CompanionPhase.due => Icons.hourglass_empty,
    // Mid-flip it is being turned over, so it reads as full again.
    CompanionPhase.justFed => Icons.hourglass_top,
  };

  @override
  CompanionPose pose(
    CompanionPhase phase,
    Size size, {
    required double drift,
    required double celebrate,
  }) {
    final centre = Offset(size.width / 2, size.height / 2);
    if (phase != CompanionPhase.justFed) return _pose(centre);
    // A single turn, eased at both ends so it lands rather than stopping.
    return _pose(centre, angle: math.pi * Curves.easeInOut.transform(celebrate));
  }
}

/// Charge draining toward the next feed, recharging when one is logged (#19).
class BatteryArt extends CompanionArt {
  const BatteryArt();

  @override
  IconData icon(CompanionPhase phase) => switch (phase) {
    CompanionPhase.easy => Icons.battery_full,
    CompanionPhase.soon => Icons.battery_3_bar,
    CompanionPhase.due => Icons.battery_alert,
    CompanionPhase.justFed => Icons.battery_charging_full,
  };

  @override
  CompanionPose pose(
    CompanionPhase phase,
    Size size, {
    required double drift,
    required double celebrate,
  }) {
    final centre = Offset(size.width / 2, size.height / 2);
    if (phase != CompanionPhase.justFed) return _pose(centre);
    // Pulses rather than moves: a battery that slides across the app bar
    // would read as a notification, not as charging.
    final pulse = (math.sin(celebrate * math.pi * 6) + 1) / 2;
    return _pose(centre, opacity: 0.45 + 0.55 * pulse);
  }
}
