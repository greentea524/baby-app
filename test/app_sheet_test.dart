import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/app_sheet.dart';

/// The keyboard is the thing that breaks bottom sheets, and it is invisible on
/// a desktop browser — so these drive it directly (#15). Before this helper,
/// focusing the bottle amount field pushed it off the top of the screen with
/// no way to scroll it back.
///
/// The sheet tests below run as native — `kIsWeb` is a compile-time constant
/// and false wherever a test runs — so they describe the platform that still
/// takes the keyboard inset. The web's rule is the pure function at the top,
/// which is the only way to reach it from a test at all.
void main() {
  group('how much to lift the sheet', () {
    test('native takes the inset: the keyboard covers the window', () {
      expect(sheetBottomInset(viewInset: 336, isWeb: false), 336);
    });

    test('the web does not: the browser already shortened the viewport', () {
      // An iPhone showed the app's own bottom navigation bar directly above
      // the keys, which can only happen if the canvas had already been
      // shrunk. Padding by the inset as well lifted the sheet a second
      // keyboard height and took the field being typed into off the top.
      expect(sheetBottomInset(viewInset: 336, isWeb: true), 0);
    });

    test('neither lifts anything with no keyboard up', () {
      expect(sheetBottomInset(viewInset: 0, isWeb: true), 0);
      expect(sheetBottomInset(viewInset: 0, isWeb: false), 0);
    });
  });

  const screen = Size(400, 800);
  const keyboard = 400.0;

  /// A form taller than the space left once the keyboard is up.
  Widget tallForm() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(key: Key('first'), height: 80, child: Text('Amount')),
      for (var i = 0; i < 6; i++) const SizedBox(height: 80),
      const SizedBox(key: Key('last'), height: 80, child: Text('Save')),
    ],
  );

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = screen;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showAppSheet<void>(context, builder: (_) => tallForm()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Raises the keyboard the way the platform does — through the view, so the
  /// MediaQuery the sheet actually reads is the one that changes.
  Future<void> raiseKeyboard(WidgetTester tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();
  }

  testWidgets('sheet content can scroll', (tester) async {
    // The whole bug in one line: a TextField asks its enclosing scrollable to
    // reveal it, and with no Scrollable ancestor that request goes nowhere.
    await openSheet(tester);
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byKey(const Key('first')),
      ),
      findsOneWidget,
    );
  });

  /// The scrolling viewport's rect — the sheet's visible window. Measured
  /// rather than any one field, because a field scrolled out of view keeps a
  /// real layout position outside the viewport, which says nothing about
  /// whether the keyboard is covering it.
  Rect viewport(WidgetTester tester) => tester.getRect(
    find
        .ancestor(
          of: find.byKey(const Key('first')),
          matching: find.byType(SingleChildScrollView),
        )
        .first,
  );

  testWidgets('the keyboard shortens the sheet instead of covering it', (
    tester,
  ) async {
    await openSheet(tester);
    await raiseKeyboard(tester);
    expect(viewport(tester).bottom, lessThanOrEqualTo(screen.height - keyboard));
  });

  testWidgets('a field below the fold can be brought into view', (
    tester,
  ) async {
    // What the report described: with the keyboard up, the form is taller
    // than the space left, and a field outside that space has to be
    // reachable rather than merely present in the tree.
    await openSheet(tester);
    await raiseKeyboard(tester);

    final last = find.byKey(const Key('last'));
    expect(
      viewport(tester).overlaps(tester.getRect(last)),
      isFalse,
      reason: 'the fixture is only meaningful if this starts out of sight',
    );

    await tester.ensureVisible(last);
    await tester.pumpAndSettle();

    final rect = tester.getRect(last);
    final window = viewport(tester);
    expect(rect.top, greaterThanOrEqualTo(window.top));
    expect(rect.bottom, lessThanOrEqualTo(window.bottom));
  });

  testWidgets('raising the keyboard does not overflow the layout', (
    tester,
  ) async {
    // A Column that cannot scroll throws here rather than shrinking, which is
    // how this would regress if the scroll view were ever removed again.
    await openSheet(tester);
    await raiseKeyboard(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the inset is released when the keyboard goes away', (
    tester,
  ) async {
    await openSheet(tester);
    await raiseKeyboard(tester);
    final raised = viewport(tester).bottom;

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(
      viewport(tester).bottom,
      greaterThan(raised),
      reason: 'the sheet should drop back down, not keep the keyboard gap',
    );
  });
}
