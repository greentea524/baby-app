import 'dart:async';

import 'package:flutter/material.dart';

/// Starts [write], closes the sheet straight away, and reports a failure on
/// whatever is underneath.
///
/// Deliberately does **not** await the write before closing. With offline
/// persistence on, a Firestore write future does not complete until the
/// server acknowledges it — the local cache is updated immediately, but the
/// future stays pending for as long as the device is offline. Awaiting it to
/// close the sheet means a caregiver with no signal watches a spinner
/// forever, force-quits, and logs the feed a second time (#21).
///
/// The record is in the local cache the moment [write] is called, so every
/// stream in the app already reflects it. Closing is the honest thing to do.
///
/// Two consequences worth knowing:
///
/// * The failure arrives on a screen that is no longer this one — hence the
///   messenger, captured before the pop, and hence [failure], a complete
///   sentence rather than a noun, because it may land long after the moment
///   that would have explained it.
/// * Offline, a rejected write is not rejected until it reaches the server.
///   A permission error can therefore surface minutes after the fact, on
///   reconnect. That is a property of the queue, not of this function; the
///   alternative is not reporting it at all.
void saveAndClose(
  BuildContext context,
  Future<void> Function() write, {
  required String failure,
}) {
  // Both looked up before the pop. Afterwards this context is defunct, which
  // is precisely when the error turns up.
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  // Future.sync rather than write(): a repository that throws on the spot —
  // a bad argument, a null check — would otherwise blow past the pop and
  // leave the sheet open with no message.
  unawaited(
    Future.sync(write).catchError((Object error) {
      messenger.showSnackBar(SnackBar(content: Text('$failure: $error')));
    }),
  );

  navigator.pop();
}
