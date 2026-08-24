import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/auth/sign_in_message.dart';

/// What the login screen says when sign-in fails.
///
/// Worth reading as prose: each of these is the only thing a caregiver who
/// cannot get in will see, and the one that started this said "An unknown
/// error occurred: Error: Database is closing/hidden [unknown]".
void main() {
  FirebaseAuthException error(String code, [String? message]) =>
      FirebaseAuthException(code: code, message: message);

  test('names the browser, not the invitation, when storage is blocked', () {
    // The failure that prompted all this. It arrives under the catch-all
    // code, so the message is the only thing to go on — and "Access is by
    // invitation" sits directly above the button, which is where the reader
    // looked instead.
    final message = signInMessage(
      error('unknown', 'An unknown error occurred: Error: Database is '
          'closing/hidden'),
    );
    expect(message, contains('blocking the storage'));
    expect(message, contains('Prevent Cross-Site Tracking'));
    expect(message, isNot(contains('unknown error occurred')));
  });

  test('and under the code Firebase does have for it', () {
    expect(
      signInMessage(error('web-storage-unsupported')),
      contains('blocking the storage'),
    );
  });

  test('recognises the other ways a browser says the same thing', () {
    for (final text in [
      'Error: Database is closing/hidden',
      'An internal error: IndexedDB is not available',
      'Access to storage is not allowed from this context.',
      'This browser: storage is not supported',
    ]) {
      expect(looksLikeBlockedStorage(text), isTrue, reason: text);
    }
  });

  test('does not mistake an ordinary failure for a storage one', () {
    expect(looksLikeBlockedStorage(null), isFalse);
    expect(looksLikeBlockedStorage('The network request failed'), isFalse);
    expect(
      signInMessage(error('unknown', 'The network request failed')),
      'Sign-in failed: The network request failed [unknown]',
    );
  });

  test('keeps the configuration messages, which name where to go', () {
    expect(
      signInMessage(error('operation-not-allowed')),
      contains('Authentication → Sign-in method'),
    );
    expect(
      signInMessage(error('unauthorized-domain')),
      contains('Authorized domains'),
    );
  });

  test('a cancelled sign-in is not an error to explain', () {
    expect(signInMessage(error('popup-closed-by-user')), 'Sign-in was cancelled.');
    expect(
      signInMessage(error('cancelled-popup-request')),
      'Sign-in was cancelled.',
    );
  });

  test('every message a caregiver might act on carries its code', () {
    // Cancellation aside: these are usually configuration, and the code is
    // what makes one searchable.
    for (final code in [
      'operation-not-allowed',
      'unauthorized-domain',
      'popup-blocked',
      'web-storage-unsupported',
      'network-request-failed',
    ]) {
      expect(signInMessage(error(code)), contains('[$code]'), reason: code);
    }
  });
}
