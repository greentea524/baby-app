import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/format/unit_system.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/insights/range_stats.dart';
import 'package:baby_app/features/insights/report_tables.dart';

/// The export report's tables, on screen (#30).
void main() {
  final start = DateTime(2026, 8, 20);
  final end = DateTime(2026, 8, 23);

  RangeStats statsFor({
    List<FeedingEvent> feedings = const [],
    List<DiaperEvent> diapers = const [],
    List<PumpingEvent> pumps = const [],
  }) => RangeStats.from(
    start: start,
    end: end,
    feedings: feedings,
    diapers: diapers,
    pumps: pumps,
  );

  FeedingEvent bottle(int day, {double ml = 120, bool snack = false}) =>
      FeedingEvent(
        id: 'f$day-$ml-$snack',
        type: FeedingType.bottle,
        startTime: DateTime(2026, 8, day, 9),
        amountMl: ml,
        isSnack: snack,
      );

  group('the two figures Insights was missing', () {
    test('counts top-ups apart from feeds', () {
      // The distinction the row exists to make: a feeds-per-day figure read
      // by a paediatrician should not have top-ups folded into it.
      final stats = statsFor(
        feedings: [bottle(20), bottle(20, ml: 30, snack: true), bottle(21)],
      );

      expect(stats.totalFeeds, 2);
      expect(stats.totalSnacks, 1);
    });

    test('but keeps their volume in the bottle total', () {
      // Volume is volume, whatever it was called.
      final stats = statsFor(
        feedings: [bottle(20, ml: 100), bottle(20, ml: 30, snack: true)],
      );
      expect(stats.totalBottleMl, 130);
    });

    test('counts pump sessions, not just what came out of them', () {
      final stats = statsFor(
        pumps: [
          PumpingEvent(id: 'p1', time: DateTime(2026, 8, 20, 7), amountMl: 90),
          PumpingEvent(id: 'p2', time: DateTime(2026, 8, 21, 7), amountMl: 60),
        ],
      );
      expect(stats.totalPumps, 2);
      expect(stats.totalPumpedMl, 150);
    });
  });

  group('days with activity', () {
    test('counts the days that had something, not the days in the window', () {
      // The series is dense on purpose — every day, so a chart shows a quiet
      // one as a gap — which means this cannot be days.length.
      final stats = statsFor(feedings: [bottle(20), bottle(22)]);

      expect(stats.days.length, 3);
      expect(stats.activeDays, 2);
    });

    test('is zero for a window with nothing in it', () {
      expect(statsFor().activeDays, 0);
    });
  });

  group('the tables', () {
    Future<void> pump(
      WidgetTester tester,
      RangeStats stats, {
      UnitSystem units = UnitSystem.metric,
      double width = 390,
      double textScale = 1.0,
    }) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: ListView(
                  children: [ReportTables(stats: stats, units: units)],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('print the overview the report prints', (tester) async {
      await pump(tester, statsFor(feedings: [bottle(20), bottle(21)]));

      expect(find.text('Total feeds'), findsOneWidget);
      expect(find.text('Avg interval between feeds'), findsOneWidget);
      expect(find.text('Days with activity'), findsOneWidget);
    });

    testWidgets('put the days first and the summary under them', (
      tester,
    ) async {
      // A summary reads as a summary when it comes after the thing it
      // summarises; the table is what the view is for.
      await pump(tester, statsFor(feedings: [bottle(20)]));

      final days = tester.getRect(find.text('Day by day'));
      final overview = tester.getRect(find.text('Overview'));
      expect(overview.top, greaterThan(days.top));
    });

    testWidgets('leave breast minutes out of the per-day columns', (
      tester,
    ) async {
      // Carried over from the printed report, where a page is read whole. On
      // screen it was a column of zeros for a bottle-fed baby and one more
      // thing to scroll past for everyone else.
      await pump(
        tester,
        statsFor(
          feedings: [
            FeedingEvent(
              id: 'b1',
              type: FeedingType.breast,
              startTime: DateTime(2026, 8, 20, 9),
              durationMinutes: 18,
            ),
          ],
        ),
      );

      expect(find.text('Breast (min)'), findsNothing);
      // The range total stays, which is where a figure nobody reads per-day
      // belongs.
      expect(find.text('Breastfeeding total'), findsOneWidget);
      expect(find.text('18 min'), findsOneWidget);
    });

    testWidgets('leave out the rows that would read zero for everyone', (
      tester,
    ) async {
      // A family that does not pump should not read two rows saying so.
      await pump(tester, statsFor(feedings: [bottle(20)]));

      expect(find.text('Pump sessions'), findsNothing);
      expect(find.text('Pumped total'), findsNothing);
      expect(find.text('Snacks / top-ups'), findsNothing);
    });

    testWidgets('and show them when there is something to show', (
      tester,
    ) async {
      await pump(
        tester,
        statsFor(
          feedings: [bottle(20), bottle(20, ml: 30, snack: true)],
          pumps: [
            PumpingEvent(id: 'p', time: DateTime(2026, 8, 20, 7), amountMl: 90),
          ],
        ),
      );

      expect(find.text('Pump sessions'), findsOneWidget);
      expect(find.textContaining('not counted as feeds'), findsOneWidget);
    });

    testWidgets('add the fl oz column only in US units', (tester) async {
      final stats = statsFor(feedings: [bottle(20)]);

      await pump(tester, stats);
      expect(find.text('Bottle (fl oz)'), findsNothing);

      await pump(tester, stats, units: UnitSystem.us);
      expect(find.text('Bottle (fl oz)'), findsOneWidget);
    });

    testWidgets('drop the pumped column for a family that does not', (
      tester,
    ) async {
      await pump(tester, statsFor(feedings: [bottle(20)]));
      expect(find.text('Pumped (ml)'), findsNothing);
    });

    testWidgets('give one row per day in the window, empty ones included', (
      tester,
    ) async {
      // Dense, matching the charts beside it: a quiet day is a row of zeros
      // rather than a day that silently is not there.
      await pump(tester, statsFor(feedings: [bottle(20)]));

      expect(find.text('Aug 20'), findsOneWidget);
      expect(find.text('Aug 21'), findsOneWidget);
      expect(find.text('Aug 22'), findsOneWidget);
    });

    testWidgets('scroll sideways on a phone rather than overflowing', (
      tester,
    ) async {
      // Seven columns will not fit 390pt, and this app has hit that failure
      // more than once.
      await pump(
        tester,
        statsFor(
          feedings: [bottle(20)],
          pumps: [
            PumpingEvent(id: 'p', time: DateTime(2026, 8, 20, 7), amountMl: 90),
          ],
        ),
        units: UnitSystem.us,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(ReportTables),
          matching: find.byType(SingleChildScrollView),
        ),
        findsWidgets,
      );
    });

    testWidgets('survive 200% text on a phone', (tester) async {
      await pump(
        tester,
        statsFor(feedings: [bottle(20), bottle(21)]),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
