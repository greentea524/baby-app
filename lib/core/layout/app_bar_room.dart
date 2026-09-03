import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'content_width.dart';

/// How Home's app bar shares itself out (#29).
///
/// Three things want that bar: the clock, the baby's name, and the next
/// appointment. Only the name is flexible, so it absorbed every shortfall —
/// on a 390pt phone it was left with 10pt and the name rendered as "J…".
/// This is the arithmetic that stops that.
class AppBarRoom {
  const AppBarRoom._(this.width);

  /// The bar's own width, which is the screen's until the content cap bites.
  factory AppBarRoom.of(BuildContext context) =>
      AppBarRoom._(math.min(MediaQuery.sizeOf(context).width, maxContentWidth));

  final double width;

  /// The least the baby's name may be left with before something else gives
  /// way. Below roughly this it stops being a name and becomes an initial.
  ///
  /// 150 rather than 120 because the switcher's width is not all name: an
  /// avatar and a chevron come out of it first, leaving perhaps 90 for the
  /// word itself. At 120 the clock still showed on a 430pt phone and the
  /// name was down to its last few characters. This puts the cliff at about
  /// 452, which is above every phone and below every tablet.
  static const nameFloor = 150.0;

  /// What the clock costs when shown.
  static const clockWidth = 112.0;

  /// What the bar spends on its own spacing around the title.
  ///
  /// Measured, not guessed: without it the arithmetic came out 48pt
  /// optimistic and put the cliff at 452, where the name was really getting
  /// 130 rather than the 178 predicted.
  static const barPadding = 48.0;

  /// Whether there is room for the clock as well as the name.
  ///
  /// Measured on width rather than platform, which gets three cases right for
  /// nothing: a narrow browser window, a phone turned on its side, and an
  /// iPad sharing the screen with something else.
  ///
  /// On a phone this comes out false, and that is the right answer twice
  /// over — the name needs the room, and the operating system is already
  /// showing the time a few points above the bar.
  bool get showsClock =>
      width - clockWidth - appointmentWidth - barPadding >= nameFloor;

  /// What the next appointment may take.
  ///
  /// A share rather than a fixed 220, so the name keeps its floor on a narrow
  /// bar instead of being the only thing that gives. The pill ellipsizes
  /// inside whatever it gets.
  double get appointmentWidth => math.min(220, width * 0.42);
}
