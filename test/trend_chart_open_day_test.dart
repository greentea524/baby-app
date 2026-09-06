import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/insights/trend_chart.dart';

/// Getting from a spike in a trend to the day behind it (#32).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpChart(
    WidgetTester tester, {
    void Function(int)? onOpenBar,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: TrendChart(
              title: 'Feeds per day',
              values: const [3, 8, 5],
              labels: const ['Jul 1', 'Jul 2', 'Jul 3'],
              onOpenBar: onOpenBar,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the middle bar. Only the horizontal position picks a bar, and the
  /// tap has to land inside the plot — the caption below it is not a target.
  Future<void> tapMiddleBar(WidgetTester tester) async {
    final chart = tester.getRect(find.byType(TrendChart));
    await tester.tapAt(Offset(chart.center.dx, chart.top + 80));
    await tester.pumpAndSettle();
  }

  group('the caption', () {
    testWidgets('still captions the bar, and does not navigate on the tap', (
      tester,
    ) async {
      // The tap is what writes the caption. Navigating on the same gesture
      // would throw you off the screen before you could read it.
      var opened = <int>[];
      await pumpChart(tester, onOpenBar: opened.add);

      expect(find.text('Tap a bar for details'), findsOneWidget);
      await tapMiddleBar(tester);

      expect(find.textContaining('Jul 2'), findsOneWidget);
      expect(opened, isEmpty);
    });

    testWidgets('grows a way into the day once a bar is chosen', (
      tester,
    ) async {
      await pumpChart(tester, onOpenBar: (_) {});

      expect(find.text('Open this day'), findsNothing);
      await tapMiddleBar(tester);
      expect(find.text('Open this day'), findsOneWidget);
    });

    testWidgets('and opens the bar that is actually selected', (tester) async {
      final opened = <int>[];
      await pumpChart(tester, onOpenBar: opened.add);

      await tapMiddleBar(tester);
      await tester.tap(find.text('Open this day'));
      await tester.pumpAndSettle();

      expect(opened, [1]);
    });

    testWidgets('offers nothing when the bars are not days', (tester) async {
      // "Feeds by hour of day" stacks the whole range into 24 columns, so no
      // single day sits behind a bar.
      await pumpChart(tester);

      await tapMiddleBar(tester);
      expect(find.textContaining('Jul 2'), findsOneWidget);
      expect(find.text('Open this day'), findsNothing);
    });
  });

  testWidgets('a screen reader can take the same route', (tester) async {
    // Each bar is its own node and announces itself as a button. Activating
    // one has to actually do what a tap does, or the caption — and the way
    // into the day it offers — is reachable only by hitting a 4px bar.
    // Disposed inline, not via addTearDown: the framework checks for a
    // leaked handle before tear-downs run.
    final handle = tester.ensureSemantics();

    await pumpChart(tester, onOpenBar: (_) {});

    // Exactly the bar's own node — the chart's summary mentions the days too.
    final bar = find.semantics.byLabel('Jul 2 · 8');
    expect(bar, findsOne);
    tester.semantics.tap(bar);
    await tester.pumpAndSettle();

    expect(find.text('Open this day'), findsOneWidget);
    handle.dispose();
  });
}
