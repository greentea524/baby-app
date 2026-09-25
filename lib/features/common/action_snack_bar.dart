import 'package:flutter/material.dart';

/// A snack bar with a button on it that still goes away by itself.
///
/// Flutter changed the default under us. A `SnackBar` with an `action` now
/// stays on screen until the action is tapped — `persist` defaults to
/// `action != null` — whatever `duration` says. So "Bottle removed · Undo" sat
/// over the fridge forever, and the caregiver notice with its 8-second
/// duration never left either: the duration was being ignored.
///
/// Both kinds of message here are offers, not questions. Undo is for the
/// moment straight after a mistake, and a copy button is for the moment
/// straight after adding someone; once the moment has passed, the bar is only
/// in the way. So every action snack bar in the app goes through this, which
/// asks for the old behaviour back explicitly rather than trusting a default
/// that has already moved once.
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
