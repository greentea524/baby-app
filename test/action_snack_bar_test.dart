import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/action_snack_bar.dart';

/// A snack bar with a button that still leaves on its own.
///
/// Flutter now keeps any snack bar with an action on screen until the action
/// is tapped. The caregiver notice ignored its own 8-second duration because
/// of it, and so did the fridge's old Undo.
void main() {
  Future<void> show(WidgetTester tester, {VoidCallback? onAction}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                actionSnackBar(
                  content: const Text('Caregiver added'),
                  actionLabel: 'Copy',
                  onAction: onAction ?? () {},
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('goes away by itself', (tester) async {
    await show(tester);
    expect(find.text('Caregiver added'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(find.text('Caregiver added'), findsNothing);
  });

  testWidgets('but not before there is time to reach the button', (
    tester,
  ) async {
    await show(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('and the button still does what it says', (tester) async {
    var copied = false;
    await show(tester, onAction: () => copied = true);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, isTrue);
  });

  test('asks not to persist, rather than trusting the default', () {
    // The default is what moved. Stated outright, a future change to it
    // cannot quietly bring the problem back.
    final bar = actionSnackBar(
      content: const Text('x'),
      actionLabel: 'y',
      onAction: () {},
    );
    expect(bar.persist, isFalse);
  });
}
