import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/format/unit_system.dart';
import 'package:baby_app/features/common/chart_text.dart';
import 'package:baby_app/features/growth/growth_chart.dart';
import 'package:baby_app/features/growth/growth_metric.dart';
import 'package:baby_app/features/insights/trend_chart.dart';

/// Reaching the charts without seeing them, and reading them at a text size
/// that is not the default (#24).
void main() {
  const width = 400.0;
  const height = 160.0;

  Future<void> pumpTrend(
    WidgetTester tester, {
    double textScale = 1.0,
    List<double> values = const [4, 7, 2],
    List<String> labels = const ['Jul 1', 'Jul 2', 'Jul 3'],
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: TrendChart(
                title: 'Feeds per day',
                values: values,
                labels: labels,
                height: height,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// Every label under [of] in the semantics tree.
  ///
  /// `find.bySemanticsLabel` walks widgets, and the per-bar nodes belong to
  /// no widget — a painter's `semanticsBuilder` produces them directly. The
  /// tree is where they actually are, so that is where to look.
  List<String> semanticLabels(WidgetTester tester, Finder of) {
    final found = <String>[];
    void visit(SemanticsNode node) {
      if (node.label.isNotEmpty) found.add(node.label);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(tester.getSemantics(of));
    return found;
  }

  /// The gutter the chart computes for [textScale] — the same call the widget
  /// makes, so the assertion is about the measuring and not about a copy of
  /// the arithmetic.
  double leftPadAt(double textScale) => TrendGeometry.measured(
    count: 3,
    labels: ChartText(
      style: const TextStyle(fontSize: 9),
      scaler: TextScaler.linear(
        textScale,
      ).clamp(maxScaleFactor: chartMaxTextScale),
    ),
    axisLabels: [
      for (final t in TrendScale.of(const [4, 7, 2]).ticks) TrendChart.trim(t),
    ],
  ).leftPad;

  group('the axis follows the text size', () {
    test('a bigger text size means a wider gutter', () {
      // The whole reason the padding stopped being a constant: at 36px fixed,
      // a scaled-up label is drawn straight through the plot.
      expect(leftPadAt(1.3), greaterThan(leftPadAt(1.0)));
    });

    test('the gutter always has room for the label in it', () {
      // The acceptance criterion, stated directly: whatever the text size,
      // the widest tick must fit in the space reserved for it.
      final ticks = [
        for (final t in TrendScale.of(const [4, 7, 2]).ticks)
          TrendChart.trim(t),
      ];
      for (final scale in [1.0, 1.5, 2.0, 3.0]) {
        final labels = ChartText(
          style: const TextStyle(fontSize: 9),
          scaler: TextScaler.linear(
            scale,
          ).clamp(maxScaleFactor: chartMaxTextScale),
        );
        expect(
          leftPadAt(scale),
          greaterThan(labels.widest(ticks)),
          reason: 'clipped at ${scale}x',
        );
      }
    });

    test('and stops growing at the cap', () {
      // Honouring 200% in the plot leaves a chart that is all axis. The
      // caption below is a real Text and scales the whole way; that is where
      // the number lives.
      expect(leftPadAt(2.0), leftPadAt(chartMaxTextScale));
      expect(leftPadAt(3.0), leftPadAt(chartMaxTextScale));
    });

    testWidgets('the chart still renders at every size', (tester) async {
      for (final scale in [1.0, 1.5, 2.0]) {
        await pumpTrend(tester, textScale: scale);
        expect(tester.takeException(), isNull, reason: 'at ${scale}x');
      }
    });
  });

  group('tapping still works at a larger text size', () {
    testWidgets('the bar under the finger is the one that gets selected', (
      tester,
    ) async {
      // The gutter moved, so a hit test working from the old 36px would now
      // be off by the difference — selecting the neighbouring day.
      await pumpTrend(tester, textScale: 2.0);

      final geometry = TrendGeometry.measured(
        count: 3,
        labels: ChartText(
          style: const TextStyle(fontSize: 9),
          scaler: TextScaler.linear(
            2.0,
          ).clamp(maxScaleFactor: chartMaxTextScale),
        ),
        axisLabels: [
          for (final t in TrendScale.of(const [4, 7, 2]).ticks)
            TrendChart.trim(t),
        ],
      );
      final plot = geometry.plot(const Size(width, height));
      final slot = plot.width / 3;
      final origin = tester.getTopLeft(
        find.descendant(
          of: find.byType(TrendChart),
          matching: find.byType(GestureDetector),
        ),
      );

      await tester.tapAt(
        origin + Offset(plot.left + slot * 1.5, plot.center.dy),
      );
      await tester.pump();
      expect(find.text('Jul 2 · 7'), findsOneWidget);
    });
  });

  group('what a screen reader finds', () {
    testWidgets('the trend chart announces itself', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpTrend(tester);

      expect(
        find.bySemanticsLabel(
          'Feeds per day. Bar chart, 3 bars, highest 7 at Jul 2, '
          'lowest 2 at Jul 3.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('every bar is reachable, not just the tapped one', (
      tester,
    ) async {
      // The captions were already there — they were only available to
      // someone who could hit a 3px column with a finger.
      final semantics = tester.ensureSemantics();
      await pumpTrend(tester);

      final labels = semanticLabels(tester, find.byType(TrendChart));
      for (final label in ['Jul 1 · 4', 'Jul 2 · 7', 'Jul 3 · 2']) {
        expect(labels, contains(label));
      }
      semantics.dispose();
    });

    testWidgets('the growth chart announces itself and its points', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: GrowthChart(
                points: [(ageMonths: 0, value: 3.4), (ageMonths: 6, value: 7)],
                metric: GrowthMetric.weight,
                units: UnitSystem.metric,
              ),
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Weight chart. 2 measurements, from 3.4 kg at 0 months '
          'to 7 kg at 6 months.',
        ),
        findsOneWidget,
      );
      final labels = semanticLabels(tester, find.byType(GrowthChart));
      expect(labels, contains('3.4 kg at 0 months'));
      expect(labels, contains('7 kg at 6 months'));
      semantics.dispose();
    });

    testWidgets('an empty range needs no chart semantics — it says so', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTrend(tester, values: const [0, 0, 0]);
      expect(find.text('Nothing logged in this range.'), findsOneWidget);
      semantics.dispose();
    });
  });
}
