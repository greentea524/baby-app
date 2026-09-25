import 'package:flutter/material.dart';

/// A snack bar with a button on it that still goes away by itself.
///
/// Flutter changed the default under us. A `SnackBar` with an `action` now
/// stays on screen until the action is tapped — `persist` defaults to
/// `action != null` — whatever `duration` says. It was found on the fridge,
/// where "Bottle removed · Undo" sat over the shelf indefinitely, and the
/// caregiver notice with its 8-second duration turned out to be doing the
/// same: the duration was being ignored.
///
/// An action on a snack bar is an offer for the moment it appears — copy the
/// message now, while you are about to send it — and once that moment has
/// passed the bar is only in the way. So every action snack bar in the app
/// goes through this, which asks for the old behaviour back explicitly rather
/// than trusting a default that has already moved once.
SnackBar actionSnackBar({
  required Widget content,
  required String actionLabel,
  required VoidCallback onAction,
  Duration duration = const Duration(seconds: 6),
}) => SnackBar(
  content: content,
  duration: duration,
  persist: false,
  action: SnackBarAction(label: actionLabel, onPressed: onAction),
);
