import 'package:baby_app/core/auth/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which OAuth parameters a sign-in attempt carries.
///
/// Worth pinning as a pure function: the string is Google's, the behaviour
/// it buys is invisible from the code, and getting it wrong looks exactly
/// like the bug it fixes — a sign-in that silently reuses the wrong account.
void main() {
  test('the ordinary sign-in asks for nothing, so it stays one tap', () {
    expect(googleSignInParameters(chooseAccount: false), isEmpty);
  });

  test('choosing an account asks Google for its picker', () {
    expect(googleSignInParameters(chooseAccount: true), {
      'prompt': 'select_account',
    });
  });
}
