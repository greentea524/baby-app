import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';

/// The track that depletes towards the next feed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpChip(WidgetTester tester, double? remaining) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: DueChip(
              text: 'Next feed in 1h · 5:00 PM',
              state: DueState.upcoming,
              remaining: remaining,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final track = find.descendant(
    of: find.byType(DueChip),
    matching: find.byType(ColoredBox),
  );

  testWidgets('draws nothing without a fraction to draw', (tester) async {
    await pumpChip(tester, null);
    expect(track, findsNothing);
  });

  testWidgets('is as wide as the time left', (tester) async {
    await pumpChip(tester, 1.0);
    final full = tester.getSize(track).width;

    await pumpChip(tester, 0.5);
    final half = tester.getSize(track).width;

    expect(half, closeTo(full / 2, 1));
    expect(full, greaterThan(20), reason: 'a full track spans the chip');
  });

  testWidgets('and has real height, rather than painting nothing', (
    tester,
  ) async {
    // The bug this guards: a childless ColoredBox inside a loosely
    // constrained FractionallySizedBox collapses to zero height, and the
    // track silently paints no pixels at all.
    await pumpChip(tester, 1.0);
    expect(tester.getSize(track).height, greaterThan(0));
  });

  testWidgets('empties when the feed is due', (tester) async {
    await pumpChip(tester, 0.0);
    expect(tester.getSize(track).width, 0);
  });
}
