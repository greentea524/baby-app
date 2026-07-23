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
}
