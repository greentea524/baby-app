import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// The OAuth parameters for a Google sign-in attempt.
///
/// Empty by default, which is what makes the ordinary case one tap: with a
/// single account signed into the browser, Google skips its chooser and
/// returns straight away. That is the right default for a household app on a
/// shared tablet — and the reason signing out and back in never asks for
/// anything.
///
/// `prompt=select_account` opts out of that, forcing the chooser so a second
/// person can reach their own account. Google's own parameter name, and the
/// only thing that reopens the picker: signing out of the app clears the
/// Firebase session, not the browser's Google session (#—).
Map<String, String> googleSignInParameters({required bool chooseAccount}) =>
    chooseAccount ? const {'prompt': 'select_account'} : const {};

/// Thin wrapper over [FirebaseAuth] exposing just what the app needs.
///
/// Web signs in through the browser; Android/iOS use `signInWithProvider`,
/// which firebase_auth backs with the platform's own OAuth flow. Neither
/// needs the `google_sign_in` plugin — that would only buy a more
/// native-looking account picker. What native builds *do* need is a real
/// `firebase_options.dart` plus the platform config files; see the
/// "Native mobile builds" section of the README.
class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Whether a browser should redirect rather than open a popup.
  ///
  /// A popup backgrounds the page that opened it, and iOS closes a hidden
  /// page's IndexedDB connections. So on an iPhone the popup would complete,
  /// come back, and fail writing the session to a database that was already
  /// closing — reported as "Database is closing/hidden" under the catch-all
  /// `unknown` code, which named neither the cause nor the cure.
  ///
  /// Desktop keeps the popup: it does not have the backgrounding problem,
  /// and a popup leaves the app's own page standing rather than reloading it.
  static bool get redirectSignIn =>
      kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Completes when signed in — or, on the redirect path, never: the browser
  /// leaves the page and the result arrives through [authStateChanges] after
  /// it comes back.
  /// Pass [chooseAccount] to make Google offer its account picker rather
  /// than returning whoever the browser already has signed in.
  Future<void> signInWithGoogle({bool chooseAccount = false}) async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters(
        googleSignInParameters(chooseAccount: chooseAccount),
      );
    if (!kIsWeb) {
      await _auth.signInWithProvider(provider);
      return;
    }
    if (redirectSignIn) {
      await _auth.signInWithRedirect(provider);
      return;
    }
    await _auth.signInWithPopup(provider);
  }

  /// Surfaces a failure from a redirect that has already come back.
  ///
  /// Without this a redirect that Google or Firebase rejected returns to a
  /// login screen with no error on it, which reads as the button having done
  /// nothing. Throws what the sign-in would have thrown; returns normally
  /// when there was no redirect, which is the ordinary case.
  Future<void> completeRedirectSignIn() async {
    if (!kIsWeb) return;
    await _auth.getRedirectResult();
  }

  /// Proves the session is fresh before something irreversible.
  ///
  /// `User.delete()` refuses with `requires-recent-login` on a session more
  /// than a few minutes old, so this has to happen first — and *before* any
  /// data is deleted rather than after. On a mobile browser it redirects,
  /// which leaves the page and comes back: done first, that costs a second
  /// tap; done in the middle, it would abandon a half-finished deletion.
  Future<void> reauthenticate() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Not signed in.',
      );
    }
    final provider = GoogleAuthProvider();
    if (!kIsWeb) {
      await user.reauthenticateWithProvider(provider);
      return;
    }
    if (redirectSignIn) {
      await user.reauthenticateWithRedirect(provider);
      return;
    }
    await user.reauthenticateWithPopup(provider);
  }

  /// Removes the account itself. Everything it owns must be gone first.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.delete();
  }

  Future<void> signOut() => _auth.signOut();
}
