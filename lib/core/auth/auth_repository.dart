import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper over [FirebaseAuth] exposing just what the app needs.
///
/// Web uses `signInWithPopup`; Android/iOS use `signInWithProvider`, which
/// firebase_auth backs with the platform's own OAuth flow. Neither needs the
/// `google_sign_in` plugin — that would only buy a more native-looking
/// account picker. What native builds *do* need is a real
/// `firebase_options.dart` plus the platform config files; see the
/// "Native mobile builds" section of the README.
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
      await _auth.signInWithProvider(provider);
    }
  }

  Future<void> signOut() => _auth.signOut();
}
