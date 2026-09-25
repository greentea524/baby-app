import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:baby_app/core/router/app_router.dart';
import 'package:baby_app/features/fridge/fridge_button.dart';

/// The way into the fridge from a pump reading.
///
/// Tested on a router of its own: the screens it sits on are pumped without
/// one in their own tests, so this is the only place a tap can be followed
/// to where it lands.
void main() {
  Future<void> pumpWithRouter(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Center(child: FridgeButton())),
        ),
        GoRoute(
          path: AppRoutes.fridge,
          builder: (_, _) => const Scaffold(body: Text('the fridge')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  testWidgets('opens the fridge', (tester) async {
    await pumpWithRouter(tester);
    await tester.tap(find.byType(FridgeButton));
    await tester.pumpAndSettle();

    expect(find.text('the fridge'), findsOneWidget);
  });

  testWidgets('pushed over where it was pressed, so Back returns there', (
    tester,
  ) async {
    // Pushed, not gone to: from nursery mode especially, the fridge is a
    // look and then back, and replacing the screen would strand whoever
    // pressed it.
    await pumpWithRouter(tester);
    await tester.tap(find.byType(FridgeButton));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isTrue);
  });

  testWidgets('is a fridge, and says so to a screen reader', (tester) async {
    // The icon is never the only thing naming where this goes.
    await pumpWithRouter(tester);

    expect(find.byIcon(Icons.kitchen_outlined), findsOneWidget);
    expect(find.byTooltip('In the fridge'), findsOneWidget);
  });
}
