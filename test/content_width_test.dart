import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/layout/content_width.dart';

/// How wide the app lays itself out (#29).
///
/// Nothing in the app was responsive, so on an iPad the phone layout
/// stretched edge to edge: at 900pt Home's content ran from x=92 to x=868,
/// putting a status row's label and its elapsed time most of a screen apart.
void main() {
  Future<Rect> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ContentWidth(
          child: Scaffold(
            body: Container(key: const Key('page'), color: Colors.blue),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(const Key('page')));
  }

  testWidgets('a phone is untouched — it is narrower than the cap', (
    tester,
  ) async {
    final page = await pumpAt(tester, const Size(390, 844));
    expect(page.left, 0);
    expect(page.right, 390);
  });

  testWidgets('an iPad in portrait is capped and centred', (tester) async {
    final page = await pumpAt(tester, const Size(834, 1194));

    expect(page.width, maxContentWidth);
    // Centred, so the margins match to within a rounding error.
    expect(page.left, moreOrLessEquals(834 - page.right, epsilon: 0.5));
  });

  testWidgets('and in landscape, where the stretch was worst', (tester) async {
    final page = await pumpAt(tester, const Size(1194, 834));

    expect(page.width, maxContentWidth);
    expect(page.left, moreOrLessEquals(1194 - page.right, epsilon: 0.5));
  });

  testWidgets('the surround is painted, not left as bare window', (
    tester,
  ) async {
    // The Scaffold now covers only the middle. Without something behind it an
    // iPad shows whatever the engine last left either side.
    await pumpAt(tester, const Size(1194, 834));

    expect(
      find.ancestor(
        of: find.byType(Center),
        matching: find.byType(ColoredBox),
      ),
      findsWidgets,
    );
  });
}
