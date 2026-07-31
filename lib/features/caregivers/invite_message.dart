import 'package:flutter/foundation.dart';

/// Text for passing a caregiver invitation on by hand.
///
/// Adding a caregiver writes a Firestore document and nothing else — no email,
/// no push. The invitee only ever sees it by signing in with the exact address
/// they were added under, so somebody has to tell them. This is the message the
/// sender copies into whatever they already use to talk to that person.
String inviteShareMessage({
  required String babyName,
  required String email,
  String? appUrl,
}) {
  final buffer = StringBuffer()
    ..writeln("I've added you as a caregiver for $babyName on Baby App.")
    ..writeln();

  if (appUrl != null && appUrl.isNotEmpty) {
    buffer.writeln('Open $appUrl and sign in with $email to accept.');
  } else {
    buffer.writeln('Sign in with $email to accept.');
  }

  // The address is the whole mechanism: the invite is stored under it, so
  // signing in with a different Google account surfaces nothing at all.
  buffer
    ..writeln()
    ..write(
      'It has to be that address — signing in with a different one '
      "won't find the invite.",
    );

  return buffer.toString();
}

/// Where the invitee should sign in, or null when there is nothing useful to
/// point them at.
///
/// On web this is the origin the sender is already using, so it is right for
/// localhost and production alike with nothing to configure. Native builds do
/// not exist yet (#4) and `Uri.base` is a file path there, so the message drops
/// the line rather than naming somewhere the invitee cannot go.
String? currentAppUrl() => kIsWeb ? Uri.base.origin : null;
