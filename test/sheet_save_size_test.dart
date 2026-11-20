import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/app_sheet.dart';

/// A sheet's Save button is a tall target on a tablet, and the standard
/// size on a phone.
void main() {
  Future<Size> saveSize(WidgetTester tester, Size screen) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Log a diaper change'),
                    FilledButton(onPressed: () {}, child: const Text('Save')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return tester.getSize(find.widgetWithText(FilledButton, 'Save'));
  }

  testWidgets('tall on an iPad, either way up, browser bars and all', (
    tester,
  ) async {
    // It was a thin strip across an iPad sheet: 40 high, easy to miss.
    for (final screen in const [Size(1180, 740), Size(820, 1100)]) {
      final size = await saveSize(tester, screen);
      expect(
        size.height,
        greaterThanOrEqualTo(TabletSheetButtons.height),
        reason: '$screen',
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('and the standard size on a phone', (tester) async {
    final size = await saveSize(tester, const Size(390, 844));
    expect(size.height, lessThan(TabletSheetButtons.height));
  });
}
