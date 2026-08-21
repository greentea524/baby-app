import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/features/insights/day_timeline_strip.dart';
import 'package:baby_app/features/insights/day_view_data.dart';
import 'package:baby_app/features/insights/diaper_mix_bar.dart';

/// The day view's two charts, and the question they exist to answer.
void main() {
  final now = DateTime(2026, 8, 20, 18);
  DiaperEvent diaper(DateTime t, DiaperType type) =>
      DiaperEvent(id: 'd$t', type: type, time: t);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  /// The bar's coloured segments. DecoratedBox rather than ColoredBox
  /// because "both" carries a gradient; the legend swatches are Containers,
  /// so they do not match.
  /// The bar itself is the only ClipRRect in the widget; the legend swatches
  /// are Containers outside it.
  Finder barSegments() => find.descendant(
    of: find.byType(ClipRRect),
    matching: find.byType(DecoratedBox),
  );

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

  group('has there been a dirty diaper', () {
    testWidgets('says so plainly when there has', (tester) async {
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 2, dirty: 1, both: 1),
          lastWithPoop: diaper(now, DiaperType.dirty),
          now: now,
        ),
      );
      expect(find.text('2 dirty diapers today.'), findsOneWidget);
    });

    testWidgets('counts a mixed one as a dirty one', (tester) async {
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 1, dirty: 0, both: 1),
          lastWithPoop: diaper(now, DiaperType.both),
          now: now,
        ),
      );
      expect(find.text('1 dirty diaper today.'), findsOneWidget);
    });

    testWidgets('when there has not, says how long it has been', (
      tester,
    ) async {
      // The whole reason this is a line of text and not a pie: an absence
      // has to be sayable, and "none yet" alone is alarming at 6am and
      // unremarkable at 6pm.
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 3, dirty: 0, both: 0),
          lastWithPoop: diaper(
            now.subtract(const Duration(hours: 19)),
            DiaperType.dirty,
          ),
          now: now,
        ),
      );
      expect(find.textContaining('None yet today'), findsOneWidget);
      expect(find.textContaining('19h'), findsOneWidget);
    });

    testWidgets('and copes with never having had one', (tester) async {
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 1, dirty: 0, both: 0),
          lastWithPoop: null,
          now: now,
        ),
      );
      expect(find.text('No dirty diaper logged yet.'), findsOneWidget);
    });
  });

  group('the diaper bar', () {
    testWidgets('keeps a zero on screen rather than hiding it', (tester) async {
      // A pie would simply omit the missing kind, which is the one thing
      // being looked for. Here it is visibly nought.
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 4, dirty: 0, both: 0),
          lastWithPoop: null,
          now: now,
        ),
      );
      expect(find.text('4 Wet'), findsOneWidget);
      expect(find.text('0 Dirty'), findsOneWidget);
      expect(find.text('0 Both'), findsOneWidget);
    });

    testWidgets('is actually drawn, at a visible size', (tester) async {
      // It was not, for a while: a childless ColoredBox in a Row gets loose
      // vertical constraints and collapses to nothing. Every text assertion
      // still passed, and the chart was an empty gap.
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 3, dirty: 1, both: 1),
          lastWithPoop: diaper(now, DiaperType.dirty),
          now: now,
        ),
      );
      final segments = barSegments();
      expect(segments, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        final size = tester.getSize(segments.at(i));
        expect(size.height, greaterThan(0), reason: 'segment $i has no height');
        expect(size.width, greaterThan(0), reason: 'segment $i has no width');
      }
    });

    testWidgets('sizes each segment to its share of the day', (tester) async {
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 3, dirty: 1, both: 0),
          lastWithPoop: diaper(now, DiaperType.dirty),
          now: now,
        ),
      );
      final segments = barSegments();
      expect(segments, findsNWidgets(2), reason: 'a zero draws no segment');
      expect(
        tester.getSize(segments.at(0)).width,
        closeTo(tester.getSize(segments.at(1)).width * 3, 1),
      );
    });

    testWidgets('survives a day with no diapers at all', (tester) async {
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 0, dirty: 0, both: 0),
          lastWithPoop: null,
          now: now,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('0 Wet'), findsOneWidget);
    });

    testWidgets('announces itself as a sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        DiaperMixBar(
          mix: (wet: 2, dirty: 1, both: 0),
          lastWithPoop: diaper(now, DiaperType.dirty),
          now: now,
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Diapers today. 3 in total, 2 wet, 1 dirty, 0 both.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the day strip', () {
    const marks = <DayMark>[
      (hour: 2.5, kind: DayMarkKind.feed),
      (hour: 9, kind: DayMarkKind.diaper),
      (hour: 14.25, kind: DayMarkKind.pump),
    ];

    testWidgets('draws a legend for the kinds that are present', (
      tester,
    ) async {
      await pump(tester, const DayTimelineStrip(marks: marks));
      expect(find.text('Feeds'), findsOneWidget);
      expect(find.text('Diapers'), findsOneWidget);
      expect(find.text('Pumping'), findsOneWidget);
      // Nothing was a top-up, so that key would be a lie.
      expect(find.text('Top-ups'), findsNothing);
    });

    testWidgets('says so when the day is empty', (tester) async {
      await pump(tester, const DayTimelineStrip(marks: []));
      expect(find.text('Nothing logged on this day.'), findsOneWidget);
    });

    testWidgets('every mark is reachable, with the time it happened', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const DayTimelineStrip(marks: marks));

      final labels = semanticLabels(tester, find.byType(DayTimelineStrip));
      expect(labels.any((l) => l.startsWith('The day as a timeline')), isTrue);
      expect(labels, contains('Feeds at 2a 30'));
      expect(labels, contains('Diapers at 9a'));
      expect(labels, contains('Pumping at 2p 15'));
      handle.dispose();
    });

    testWidgets('does not overflow at a large text size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: SizedBox(width: 320, child: DayTimelineStrip(marks: marks)),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
