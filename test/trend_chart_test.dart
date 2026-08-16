import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/common/chart_text.dart';
import 'package:baby_app/features/insights/trend_chart.dart';

/// The bars carry no labels of their own, so tapping one is the only way to
/// read the number behind it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const width = 400.0;
  const height = 160.0;

  /// The axis labels as the chart draws them at the default text size.
  ChartText plainLabels() => const ChartText(
    style: TextStyle(fontSize: 9),
    scaler: TextScaler.noScaling,
  );

  /// The geometry the widget would compute for [values], so a test taps
  /// where the chart actually put the column.
  TrendGeometry geometryFor(
    List<double> values, {
    String Function(double)? axisFormat,
    String Function(double)? secondaryFormat,
  }) {
    final format = axisFormat ?? TrendChart.trim;
    final ticks = TrendScale.of(values).ticks;
    return TrendGeometry.measured(
      count: values.length,
      labels: plainLabels(),
      axisLabels: [for (final t in ticks) format(t)],
      secondaryLabels: secondaryFormat == null
          ? null
          : [for (final t in ticks) secondaryFormat(t)],
    );
  }

  Future<void> pumpChart(
    WidgetTester tester, {
    required List<double> values,
    required List<String> labels,
    String Function(double)? valueFormat,
    String Function(double)? axisFormat,
    String Function(double)? secondaryFormat,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: TrendChart(
              title: 'Feeds per day',
              values: values,
              labels: labels,
              height: height,
              valueFormat: valueFormat,
              axisFormat: axisFormat,
              secondaryFormat: secondaryFormat,
            ),
          ),
        ),
      ),
    ),
  );

  /// Taps the middle of the column for [index].
  Future<void> tapBar(
    WidgetTester tester,
    int index,
    List<double> values, {
    String Function(double)? axisFormat,
    String Function(double)? secondaryFormat,
  }) async {
    final geometry = geometryFor(
      values,
      axisFormat: axisFormat,
      secondaryFormat: secondaryFormat,
    );
    final plot = geometry.plot(const Size(width, height));
    final slot = plot.width / values.length;
    // Anchor to the chart's own gesture area: Scaffold and Material insert
    // CustomPaints of their own, so byType(CustomPaint).first is not it.
    final origin = tester.getTopLeft(
      find.descendant(
        of: find.byType(TrendChart),
        matching: find.byType(GestureDetector),
      ),
    );
    await tester.tapAt(
      origin + Offset(plot.left + slot * (index + 0.5), plot.center.dy),
    );
    await tester.pump();
  }

  testWidgets('prompts before anything is selected', (tester) async {
    await pumpChart(
      tester,
      values: [1, 2, 3],
      labels: ['Jul 1', 'Jul 2', 'Jul 3'],
    );
    expect(find.text('Tap a bar for details'), findsOneWidget);
  });

  testWidgets('tapping a bar reports its day and value', (tester) async {
    await pumpChart(
      tester,
      values: [4, 7, 2],
      labels: ['Jul 1', 'Jul 2', 'Jul 3'],
    );
    await tapBar(tester, 1, [4, 7, 2]);
    expect(find.text('Jul 2 · 7'), findsOneWidget);
    expect(find.text('Tap a bar for details'), findsNothing);
  });

  testWidgets('tapping another bar moves the selection', (tester) async {
    await pumpChart(
      tester,
      values: [4, 7, 2],
      labels: ['Jul 1', 'Jul 2', 'Jul 3'],
    );
    await tapBar(tester, 1, [4, 7, 2]);
    await tapBar(tester, 2, [4, 7, 2]);
    expect(find.text('Jul 3 · 2'), findsOneWidget);
    expect(find.text('Jul 2 · 7'), findsNothing);
  });

  testWidgets('a day with nothing logged still reports zero', (tester) async {
    // No bar is drawn for an empty day, so hit-testing the drawn shape would
    // make those days unselectable — and "nothing that day" is an answer.
    await pumpChart(
      tester,
      values: [4, 0, 2],
      labels: ['Jul 1', 'Jul 2', 'Jul 3'],
    );
    await tapBar(tester, 1, [4, 0, 2]);
    expect(find.text('Jul 2 · 0'), findsOneWidget);
  });

  testWidgets('the caption carries the second unit when there is one', (
    tester,
  ) async {
    await pumpChart(
      tester,
      values: [240],
      labels: ['Jul 1'],
      valueFormat: (v) => '${v.toStringAsFixed(0)} ml',
      secondaryFormat: (v) => '${(v / 29.5735).toStringAsFixed(1)} fl oz',
    );
    await tapBar(tester, 0, [
      240,
    ], secondaryFormat: (v) => '${(v / 29.5735).toStringAsFixed(1)} fl oz');
    expect(find.text('Jul 1 · 240 ml (8.1 fl oz)'), findsOneWidget);
  });

  testWidgets('a narrow axis format never reaches the caption', (tester) async {
    // A duration is abbreviated on the axis to keep the gutter narrow — but
    // the caption has the room to spell the tapped value out in full, and
    // that is the number the tap was for.
    await pumpChart(
      tester,
      values: [400],
      labels: ['Jul 1'],
      valueFormat: (v) => '${v ~/ 60}h ${(v % 60).toInt()}m',
      axisFormat: (v) => '${(v / 60).toStringAsFixed(1)}h',
    );
    await tapBar(tester, 0, [
      400,
    ], axisFormat: (v) => '${(v / 60).toStringAsFixed(1)}h');
    expect(find.text('Jul 1 · 6h 40m'), findsOneWidget);
  });

  testWidgets('changing the range clears the selection', (tester) async {
    // The index belonged to the old range; keeping it would caption a day that
    // is no longer plotted.
    await pumpChart(
      tester,
      values: [4, 7, 2],
      labels: ['Jul 1', 'Jul 2', 'Jul 3'],
    );
    await tapBar(tester, 1, [4, 7, 2]);
    expect(find.text('Jul 2 · 7'), findsOneWidget);

    await pumpChart(tester, values: [9, 9], labels: ['Aug 1', 'Aug 2']);
    await tester.pump();
    expect(find.text('Tap a bar for details'), findsOneWidget);
  });

  testWidgets('an empty range says so rather than offering a tap', (
    tester,
  ) async {
    await pumpChart(tester, values: [0, 0], labels: ['Jul 1', 'Jul 2']);
    expect(find.text('Nothing logged in this range.'), findsOneWidget);
    expect(find.text('Tap a bar for details'), findsNothing);
  });

  group('TrendGeometry', () {
    test('maps a position to the column under it', () {
      const geometry = TrendGeometry(
        count: 4,
        leftPad: 36,
        rightPad: 8,
        bottomPad: 20,
      );
      const size = Size(width, height);
      final plot = geometry.plot(size);
      final slot = plot.width / 4;

      for (var i = 0; i < 4; i++) {
        expect(
          geometry.indexAt(Offset(plot.left + slot * (i + 0.5), 50), size),
          i,
        );
      }
    });

    test('ignores height, so a short bar is still reachable', () {
      // Bars can be a pixel tall; requiring a vertical hit would make the
      // smallest days the hardest to read.
      const geometry = TrendGeometry(
        count: 3,
        leftPad: 36,
        rightPad: 8,
        bottomPad: 20,
      );
      const size = Size(width, height);
      final plot = geometry.plot(size);
      expect(geometry.indexAt(Offset(plot.left + 1, plot.top + 1), size), 0);
      expect(geometry.indexAt(Offset(plot.left + 1, plot.bottom - 1), size), 0);
    });

    test('returns null outside the plot', () {
      const geometry = TrendGeometry(
        count: 3,
        leftPad: 36,
        rightPad: 8,
        bottomPad: 20,
      );
      const size = Size(width, height);
      final plot = geometry.plot(size);
      expect(geometry.indexAt(Offset(plot.left - 5, 50), size), isNull);
      expect(geometry.indexAt(Offset(plot.right + 5, 50), size), isNull);
    });

    test('leaves room on the right for a second unit', () {
      const size = Size(width, height);
      final plain = geometryFor([10]).plot(size);
      final dual = geometryFor([
        10,
      ], secondaryFormat: (v) => '${v.toStringAsFixed(1)} fl oz').plot(size);
      expect(dual.right, lessThan(plain.right));
    });
  });
}
