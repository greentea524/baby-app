import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase options with the auth helper moved onto the app's own origin.
///
/// Firebase Auth on web does its work through a helper served at
/// `/__/auth/` on the project's `authDomain` — `baby-6f5b0.firebaseapp.com`
/// as generated. Whenever the app is served from anything else, that helper
/// is a third party, and a browser that partitions third-party storage will
/// not give it IndexedDB. Safari does exactly that by default, which is why
/// signing in on an iPhone failed with "Database is closing/hidden" while
/// desktop Chrome was fine.
///
/// Firebase Hosting serves the `/__/auth/` paths on every site in the
/// project, so pointing `authDomain` at whatever host is serving the page
/// makes the helper same-origin. Taken from [Uri.base] rather than written
/// down: a hard-coded domain is a guess that goes stale the moment a custom
/// domain is added, and this is right by construction.
FirebaseOptions sameOriginAuth(FirebaseOptions options) {
  if (!kIsWeb) return options;
  return options.copyWith(
    authDomain: authHostFor(
      pageHost: Uri.base.host,
      fallback: options.authDomain ?? '',
    ),
  );
}

/// Which host should serve the auth helper for a page served from
/// [pageHost], given the [fallback] the project was generated with.
///
/// Split out from [sameOriginAuth] so the rule is testable: `kIsWeb` is a
/// compile-time constant and false everywhere a test runs, so anything
/// behind it is never reached by the suite.
String authHostFor({required String pageHost, required String fallback}) {
  // A dev server is not Firebase Hosting and serves no helper of its own, so
  // localhost keeps the generated domain — which works there, being one of
  // the origins Firebase authorises out of the box.
  if (pageHost.isEmpty || _isLocal(pageHost)) return fallback;
  return pageHost;
}

bool _isLocal(String host) =>
    host == 'localhost' ||
    host == '127.0.0.1' ||
    host == '::1' ||
    host == '0.0.0.0';
