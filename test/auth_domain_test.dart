import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/auth/auth_domain.dart';

/// Where the web auth helper is served from.
///
/// Firebase Auth does its browser work through a helper at `/__/auth/` on
/// the project's authDomain. Generated, that is `<project>.firebaseapp.com`
/// — a third party to any page served from anywhere else, and Safari will
/// not give a third party IndexedDB. Signing in on an iPhone failed with
/// "Database is closing/hidden" on exactly that.
void main() {
  const generated = 'baby.firebaseapp.com';

  String hostFor(String pageHost) =>
      authHostFor(pageHost: pageHost, fallback: generated);

  test('follows the host the page came from', () {
    // The fix: same-origin by construction, so the helper is never a third
    // party however the app is served.
    expect(hostFor('baby.web.app'), 'baby.web.app');
  });

  test('follows a custom domain too, which is the point of not guessing', () {
    // A hard-coded hosting domain would be right until the day someone adds
    // a domain of their own, and wrong silently after it.
    expect(hostFor('tracker.example.com'), 'tracker.example.com');
  });

  test('leaves the generated domain alone on a dev server', () {
    // localhost is not Firebase Hosting and serves no helper, so rewriting
    // to it would break `flutter run -d chrome` to fix a phone.
    expect(hostFor('localhost'), generated);
    expect(hostFor('127.0.0.1'), generated);
  });

  test('falls back rather than rewriting to nothing', () {
    expect(hostFor(''), generated);
  });

  test('copyWith carries the whole option set, not just what it names', () {
    // What the rewrite depends on. If copyWith dropped a field the app would
    // come up misconfigured in a way no widget test would notice.
    const options = FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'baby',
      authDomain: generated,
    );
    final moved = options.copyWith(authDomain: 'baby.web.app');
    expect(moved.authDomain, 'baby.web.app');
    expect(moved.apiKey, 'k');
    expect(moved.appId, 'a');
    expect(moved.messagingSenderId, 's');
    expect(moved.projectId, 'baby');
  });
}
