import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/app_update_prompt.dart';

/// The "new version ready" prompt (#34). Mounted in MaterialApp's builder,
/// as the app does, so it is above every route.
void main() {
  late void Function() fire;
  late int applied;

  Future<void> pumpApp(WidgetTester tester, {bool alreadyWaiting = false}) {
    applied = 0;
    return tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppUpdatePrompt(
          onReady: (ready) {
            fire = ready;
            if (alreadyWaiting) ready();
          },
          apply: () => applied++,
          child: child!,
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    );
  }

  testWidgets('says nothing until a new version is waiting', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('offers a reload once one is', (tester) async {
    await pumpApp(tester);
    fire();
    await tester.pumpAndSettle();
    expect(find.text('A new version of the app is ready'), findsOneWidget);

    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(applied, 1);
  });

  testWidgets('even into an app sitting idle, drawing nothing', (tester) async {
    // The browser says so between frames. Waiting for the next frame
    // without asking for one waited forever: nothing was on screen.
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    fire();
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('including one that finished before the app started', (
    tester,
  ) async {
    await pumpApp(tester, alreadyWaiting: true);
    await tester.pumpAndSettle();
    expect(find.text('A new version of the app is ready'), findsOneWidget);
  });

  testWidgets('and says it once, however often it is told', (tester) async {
    await pumpApp(tester);
    fire();
    fire();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('and stays until it is acted on', (tester) async {
    await pumpApp(tester);
    fire();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 10));
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
