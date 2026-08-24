import 'package:firebase_auth/firebase_auth.dart';

/// What to tell someone whose sign-in failed.
///
/// Pure, and its own file, so the whole mapping can be read and tested as
/// prose. Every message keeps the raw code: these failures are usually
/// configuration, and a code is what makes one searchable.
String signInMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'operation-not-allowed':
      return 'Google sign-in is not enabled for this Firebase project. '
          'Enable it in Authentication → Sign-in method. [${e.code}]';
    case 'unauthorized-domain':
      return 'This domain is not authorized for sign-in. Add it under '
          'Authentication → Settings → Authorized domains. [${e.code}]';
    case 'popup-blocked':
      return 'The sign-in popup was blocked by the browser. Allow popups '
          'for this site and try again. [${e.code}]';
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
      return 'Sign-in was cancelled.';
    case 'web-storage-unsupported':
      return _blockedStorage(e.code);
    default:
      // Firebase could not place the error, so the reason is in the text
      // rather than the code. The one worth naming is browser storage:
      // Firebase Auth keeps the session in IndexedDB, and a browser that
      // withholds it fails here with nothing that reads like a cause.
      if (looksLikeBlockedStorage(e.message)) return _blockedStorage(e.code);
      return 'Sign-in failed: ${e.message ?? e.code} [${e.code}]';
  }
}

/// Whether an unmapped failure is really the browser refusing storage.
///
/// Matched on the message because Firebase reports these under the catch-all
/// `unknown` code. An iPhone hit "An unknown error occurred: Error: Database
/// is closing/hidden", which sent the reader looking at the invitation line
/// above the button rather than at Safari's settings.
bool looksLikeBlockedStorage(String? message) {
  if (message == null) return false;
  final m = message.toLowerCase();
  return m.contains('database is closing') ||
      m.contains('indexeddb') ||
      m.contains('storage is not supported') ||
      m.contains('access to storage is not allowed');
}

String _blockedStorage(String code) =>
    'This browser is blocking the storage sign-in needs. Try a normal window '
    'rather than a private one, and in Safari turn off Settings → Apps → '
    'Safari → Prevent Cross-Site Tracking for this site. [$code]';
