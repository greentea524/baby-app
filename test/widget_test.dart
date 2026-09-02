import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/auth/login_screen.dart';

void main() {
  testWidgets('login screen shows Google sign-in button', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Baby App'), findsOneWidget);
  });

  testWidgets('and a way out for the second person in the house', (
    tester,
  ) async {
    // Signing out ends the Firebase session, not the browser's Google one,
    // so the primary button takes whoever is already signed in without
    // asking. Someone else needs a door that is not that one.
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );

    final other = find.widgetWithText(TextButton, 'Use a different account');
    expect(other, findsOneWidget);
    // Below the primary action: it is the exception, not the way in.
    expect(
      tester.getTopLeft(other).dy,
      greaterThan(tester.getTopLeft(find.text('Continue with Google')).dy),
    );
  });
}
