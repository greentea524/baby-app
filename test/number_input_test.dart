import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/format/volume_entry.dart';
import 'package:baby_app/features/common/number_input.dart';
import 'package:baby_app/features/common/volume_field.dart';

/// Keeping a minus sign out of a quantity (#22).
///
/// The rules refuse a negative amount, and the sheet no longer waits for the
/// write — so a typed "-40" would look saved and then be rejected minutes
/// later, on a screen that has moved on. Cheapest fix is at the keyboard.
void main() {
  Future<TextEditingController> pumpField(
    WidgetTester tester,
    List<TextInputFormatter> formatters,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(controller: controller, inputFormatters: formatters),
        ),
      ),
    );
    return controller;
  }

  group('amounts', () {
    testWidgets('a minus sign never lands', (tester) async {
      final controller = await pumpField(tester, positiveDecimalInput);
      await tester.enterText(find.byType(TextField), '-40');
      expect(controller.text, '40');
    });

    testWidgets('decimals still work', (tester) async {
      final controller = await pumpField(tester, positiveDecimalInput);
      await tester.enterText(find.byType(TextField), '62.5');
      expect(controller.text, '62.5');
    });

    testWidgets('so does nothing at all', (tester) async {
      // An empty amount is legitimate — a breast feed has no volume — so the
      // formatter must not conjure a zero.
      final controller = await pumpField(tester, positiveDecimalInput);
      await tester.enterText(find.byType(TextField), '');
      expect(controller.text, '');
    });
  });

  group('durations', () {
    testWidgets('whole minutes only', (tester) async {
      final controller = await pumpField(tester, wholeNumberInput);
      await tester.enterText(find.byType(TextField), '-12.5');
      expect(controller.text, '125');
    });
  });

  testWidgets('the shared amount field carries the formatter', (tester) async {
    // Both the bottle and pumping forms go through VolumeField, so this is
    // the one that covers them.
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VolumeField(
            controller: controller,
            unit: VolumeUnit.ml,
            onUnitChanged: (_, _) {},
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '-40');
    expect(controller.text, '40');
  });
}
