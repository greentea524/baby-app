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

    test('the web takes it when the screen kept its height', () {
      // Reported: editing a bottle's amount on a phone, the field was under
      // the keyboard. While a field is being edited, Flutter keeps the screen
      // its full height and reports the keyboard as an inset; ignoring the
      // inset on the web left the sheet underneath the keys.
      expect(
        sheetBottomInset(
          viewInset: 336,
          height: 800,
          fullHeight: 800,
          isWeb: true,
        ),
        336,
      );
    });

    test('but not twice, when the browser already shrank the screen', () {
      // An iPhone once showed the app's own bottom bar directly above the
      // keys: the page had been shrunk for the keyboard, and the inset was
      // reported as well. Padding by it lifted the sheet a second keyboard
      // height and took the field off the top.
      expect(
        sheetBottomInset(
          viewInset: 336,
          height: 464,
          fullHeight: 800,
          isWeb: true,
        ),
        0,
      );
    });

    test('and only the rest, when it shrank part of the way', () {
      expect(
        sheetBottomInset(
          viewInset: 336,
          height: 700,
          fullHeight: 800,
          isWeb: true,
        ),
        236,
      );
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
    expect(
      viewport(tester).bottom,
      lessThanOrEqualTo(screen.height - keyboard),
    );
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

  group('on the web', () {
    // Editing a bottle on a phone, the amount being typed was under the
    // keyboard. Driven here as the web: the keyboard as an inset, with the
    // screen either kept at full height or shrunk for it as well.
    setUp(() => debugSheetIsWeb = true);
    tearDown(() => debugSheetIsWeb = null);

    Future<void> openWithField(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = screen;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppSheet<void>(
                  context,
                  builder: (_) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 4; i++) const SizedBox(height: 80),
                      const TextField(key: Key('amount')),
                      for (var i = 0; i < 3; i++) const SizedBox(height: 80),
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
      await tester.tap(find.byKey(const Key('amount')));
      await tester.pumpAndSettle();
    }

    testWidgets('the field being typed in stays above the keys', (
      tester,
    ) async {
      await openWithField(tester);
      // Full height kept, keyboard as an inset: how Flutter reports it
      // while a field is being edited.
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('amount')), '95');
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byKey(const Key('amount')));
      expect(field.bottom, lessThanOrEqualTo(screen.height - keyboard));
      expect(field.top, greaterThanOrEqualTo(0));
    });

    testWidgets('and is not lifted twice when the page shrank too', (
      tester,
    ) async {
      await openWithField(tester);
      // The page shrunk for the keyboard, and the inset reported as well.
      tester.view.physicalSize = const Size(400, 800 - keyboard);
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byKey(const Key('amount')));
      expect(field.top, greaterThanOrEqualTo(0), reason: 'not off the top');
      expect(field.bottom, lessThanOrEqualTo(800 - keyboard));
    });
  });
}
