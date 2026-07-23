import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper over [FirebaseAuth] exposing just what the app needs.
///
/// Web uses `signInWithPopup` (no extra plugin needed); native platforms
/// will need the `google_sign_in` flow, added when mobile targets ship.
class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
    } else {
      // Mobile targets: swap in the google_sign_in credential flow here.
      await _auth.signInWithProvider(provider);
    }
  }

  Future<void> signOut() => _auth.signOut();
}
