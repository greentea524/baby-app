import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/app_sheet.dart';

/// How far a log sheet lifts itself above the keyboard.
///
/// An iPhone pushed the bottle amount — and then the solids food field —
/// clean off the top of the screen while typing into it. The screenshot named
/// the cause: the app's own bottom navigation bar was sitting directly above
/// the keys, which can only happen if the browser had already shortened the
/// canvas. Padding by `viewInsets.bottom` on top of that lifted the sheet a
/// second keyboard height.
void main() {
  group('the keyboard inset', () {
    test('is taken on native, where the keyboard covers the window', () {
      expect(sheetBottomInset(viewInset: 336, isWeb: false), 336);
    });

    test('is ignored on the web, where the browser already resized', () {
      expect(sheetBottomInset(viewInset: 336, isWeb: true), 0);
    });

    test('is nothing either way with no keyboard up', () {
      expect(sheetBottomInset(viewInset: 0, isWeb: true), 0);
      expect(sheetBottomInset(viewInset: 0, isWeb: false), 0);
    });
  });

  group('the sheet itself', () {
    Future<void> open(WidgetTester tester, {double keyboard = 0}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAppSheet<void>(
                    context,
                    builder: (_) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const TextField(key: Key('first')),
                        for (var i = 0; i < 24; i++)
                          const SizedBox(height: 40, child: Placeholder()),
                        const Text('bottom'),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      if (keyboard > 0) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await tester.pumpAndSettle();
      }
    }

    testWidgets('keeps its content on screen when the keyboard opens', (
      tester,
    ) async {
      // The regression in one assertion: the first field must not be lifted
      // off the top of the screen by the keyboard appearing.
      await open(tester);
      final before = tester.getRect(find.byKey(const Key('first')));
      expect(before.top, greaterThanOrEqualTo(0));

      await open(tester, keyboard: 336);
      final after = tester.getRect(find.byKey(const Key('first')));
      expect(after.top, greaterThanOrEqualTo(0));
    });

    testWidgets('scrolls, so a field below the fold is still reachable', (
      tester,
    ) async {
      // The other half of why the inset can be dropped safely: content lives
      // in a scroll view, so anything the keyboard covers can be scrolled up.
      await open(tester, keyboard: 336);

      // On position, not on the finder: a SingleChildScrollView builds every
      // child, so find.text matches rows that are nowhere near the screen.
      const screenHeight = 844.0;
      expect(
        tester.getRect(find.text('bottom')).top,
        greaterThan(screenHeight),
        reason: 'the fixture should start with this row below the fold',
      );

      await tester.drag(find.byType(TextField), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.text('bottom')).bottom,
        lessThanOrEqualTo(screenHeight),
      );
    });
  });
}
