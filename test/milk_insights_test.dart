import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/format/unit_system.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/milk_kind.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/insights/insights_providers.dart';
import 'package:baby_app/features/insights/insights_screen.dart';
import 'package:baby_app/features/insights/milk_charts.dart';
import 'package:baby_app/features/insights/milk_mix.dart';
import 'package:baby_app/features/insights/range_stats.dart';
import 'package:baby_app/features/insights/trend_chart.dart';
import 'package:baby_app/features/timeline/day_stats.dart';

/// Is the baby fed on pumped milk, and what else is in the bottles (#33).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  FeedingEvent bottle(
    double ml,
    MilkKind? milk, {
    int daysAgo = 0,
    int hour = 9,
    FeedingType type = FeedingType.bottle,
  }) => FeedingEvent(
    id: 'f$ml$milk$daysAgo$hour',
    type: type,
    startTime: DateTime(today.year, today.month, today.day - daysAgo, hour),
    amountMl: ml,
    milk: milk,
  );

  PumpingEvent pumped(double ml, {int daysAgo = 0, int hour = 7}) =>
      PumpingEvent(
        id: 'p$ml$daysAgo$hour',
        time: DateTime(today.year, today.month, today.day - daysAgo, hour),
        amountMl: ml,
      );

  group('the numbers', () {
    test('a day splits its bottles by milk', () {
      final stats = DayStats.from([
        bottle(120, MilkKind.expressed),
        bottle(60, MilkKind.expressed, hour: 12),
        bottle(90, MilkKind.formula, hour: 15),
        // Logged before the question was asked.
        bottle(100, null, hour: 18),
        // A breastfeed has no volume to split.
        FeedingEvent(
          id: 'b',
          type: FeedingType.breast,
          startTime: DateTime(today.year, today.month, today.day, 20),
          durationMinutes: 15,
        ),
      ], const []);

      expect(stats.bottleMlByMilk, {
        MilkKind.expressed: 180,
        MilkKind.formula: 90,
        null: 100,
      });
      expect(stats.bottleMl, 370);
    });

    test('a range adds its days up', () {
      final stats = RangeStats.from(
        start: today.subtract(const Duration(days: 6)),
        end: today.add(const Duration(days: 1)),
        feedings: [
          bottle(120, MilkKind.expressed, daysAgo: 3),
          bottle(120, MilkKind.expressed, daysAgo: 1),
          bottle(150, MilkKind.wholeMilk),
        ],
        diapers: const [],
      );
      expect(stats.totalBottleMlByMilk, {
        MilkKind.expressed: 240,
        MilkKind.wholeMilk: 150,
      });
    });

    test('shares and pump coverage', () {
      final mix = MilkMix.of({MilkKind.expressed: 300, MilkKind.formula: 100});
      expect(mix.totalMl, 400);
      expect(mix.share(MilkKind.expressed), 0.75);
      expect(mix.pumpCoverage(330), closeTo(1.1, 1e-9));
      // Nothing to measure against: not "infinitely ahead".
      expect(const MilkMix(formulaMl: 100).pumpCoverage(200), isNull);
    });
  });

  group('the sentences', () {
    test('say the breast milk share of what is known', () {
      expect(
        MilkMixBar.headline(const MilkMix(breastMilkMl: 300)),
        'All breast milk.',
      );
      expect(
        MilkMixBar.headline(const MilkMix(breastMilkMl: 300, formulaMl: 100)),
        'Breast milk was 75% of bottles.',
      );
      // Unrecorded bottles are left out of the share, and it says so.
      expect(
        MilkMixBar.headline(
          const MilkMix(breastMilkMl: 300, formulaMl: 100, unknownMl: 400),
        ),
        'Breast milk was 75% of bottles (of bottles with a milk type '
        'recorded).',
      );
      expect(
        MilkMixBar.headline(const MilkMix(unknownMl: 100)),
        'Milk type was not recorded for these bottles.',
      );
    });

    test('say whether pumping kept up', () {
      const fed = MilkMix(breastMilkMl: 500);
      expect(
        PumpedVsFed.headline(550, fed),
        'Pumped 110% of the breast milk fed.',
      );
      expect(
        PumpedVsFed.headline(400, fed),
        'Pumped 80% of the breast milk fed — the rest came from milk pumped '
        'earlier.',
      );
      expect(
        PumpedVsFed.headline(200, const MilkMix(formulaMl: 100)),
        'No breast milk fed from bottles.',
      );
    });
  });

  group('the stacked bottle chart', () {
    testWidgets('names each milk, and breaks a tapped day down', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrendChart(
              title: 'Bottle per day (ml)',
              values: const [240, 300],
              labels: const ['9/1', '9/2'],
              segments: const [
                TrendSegment(
                  label: 'Breast milk',
                  colour: Colors.purple,
                  values: [240, 180],
                ),
                TrendSegment(
                  label: 'Formula',
                  colour: Colors.green,
                  values: [0, 120],
                ),
                TrendSegment(
                  label: 'Whole milk',
                  colour: Colors.blue,
                  values: [0, 0],
                ),
              ],
            ),
          ),
        ),
      );

      // A key for the two that appear, and none for the one that does not.
      expect(find.text('Breast milk'), findsOneWidget);
      expect(find.text('Formula'), findsOneWidget);
      expect(find.text('Whole milk'), findsNothing);

      final chart = tester.getRect(find.byType(CustomPaint).last);
      await tester.tapAt(Offset(chart.right - 20, chart.center.dy));
      await tester.pumpAndSettle();
      expect(
        find.text('9/2 · 300 — Breast milk 180 · Formula 120'),
        findsOneWidget,
      );
    });
  });

  group('on Insights', () {
    final baby = Baby(
      id: 'baby1',
      name: 'Ada',
      birthDate: DateTime(2026, 2, 1),
      ownerUid: 'alice',
      members: const {'alice': CaregiverRole.owner},
    );

    Future<void> pumpInsights(
      WidgetTester tester, {
      required List<FeedingEvent> feeds,
      List<PumpingEvent> pumps = const [],
      bool pumpingShown = true,
      bool day = false,
      Size size = const Size(390, 844),
      double textScale = 1.0,
    }) async {
      SharedPreferences.setMockInitialValues({
        'show_pumping_action': pumpingShown,
        'unit_system': 'metric',
      });
      final stored = await SharedPreferences.getInstance();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      InsightsData dataFor(InsightsRange range) {
        final start = DateTime(
          today.year,
          today.month,
          today.day - range.days + 1,
        );
        bool inside(DateTime t) => !t.isBefore(start);
        final f = [
          for (final e in feeds)
            if (inside(e.startTime)) e,
        ];
        final p = [
          for (final e in pumps)
            if (inside(e.time)) e,
        ];
        return (
          stats: RangeStats.from(
            start: start,
            end: today.add(const Duration(days: 1)),
            feedings: f,
            diapers: const [],
            pumps: p,
          ),
          feedings: f,
          diapers: const [],
          pumps: p,
        );
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
            recentDiapersProvider.overrideWith((ref) => Stream.value([])),
            for (final range in InsightsRange.values)
              rangeStatsProvider(
                range,
              ).overrideWith((ref) async => dataFor(range)),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: const InsightsScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (day) {
        await tester.tap(find.text('Day'));
        await tester.pumpAndSettle();
      }
    }

    Future<void> scrollTo(WidgetTester tester, Finder finder) =>
        tester.scrollUntilVisible(
          finder,
          200,
          scrollable: find.byType(Scrollable).last,
        );

    final mixed = [
      bottle(120, MilkKind.expressed, daysAgo: 2),
      bottle(120, MilkKind.expressed, daysAgo: 1),
      bottle(90, MilkKind.formula, daysAgo: 1, hour: 14),
      bottle(150, MilkKind.expressed),
    ];
    final pumpedWeek = [
      pumped(200, daysAgo: 2),
      pumped(150, daysAgo: 1),
      pumped(80),
    ];

    testWidgets('the week shows both, over the week', (tester) async {
      await pumpInsights(tester, feeds: mixed, pumps: pumpedWeek);

      await scrollTo(tester, find.text('Bottles by milk'));
      expect(find.text('Bottle feeds over these 7 days, by volume'), findsOne);
      expect(find.text('Breast milk 390 ml · 81%'), findsOneWidget);
      expect(find.text('Formula 90 ml · 19%'), findsOneWidget);
      expect(find.text('Breast milk was 81% of bottles.'), findsOneWidget);

      await scrollTo(tester, find.text('Pumped vs fed'));
      expect(find.text('Pumped · 430 ml'), findsOneWidget);
      expect(find.text('Fed as breast milk · 390 ml'), findsOneWidget);
      expect(find.text('Pumped 110% of the breast milk fed.'), findsOneWidget);
    });

    testWidgets('the bottle chart is split by milk', (tester) async {
      await pumpInsights(tester, feeds: mixed, pumps: pumpedWeek);
      await scrollTo(tester, find.text('Bottle per day (ml)'));
      final chart = tester.widget<TrendChart>(
        find.byWidgetPredicate(
          (w) => w is TrendChart && w.title.startsWith('Bottle per day'),
        ),
      );
      expect(chart.segments, isNotNull);
      expect(chart.segments!.map((s) => s.label), [
        'Breast milk',
        'Formula',
        'Whole milk',
        'Not recorded',
      ]);
    });

    testWidgets('the day shows today, and says why it jumps about', (
      tester,
    ) async {
      await pumpInsights(tester, feeds: mixed, pumps: pumpedWeek, day: true);

      await scrollTo(tester, find.text('Pumped vs fed'));
      expect(find.text('All breast milk.'), findsOneWidget);
      expect(find.textContaining('often fed tomorrow'), findsOneWidget);
      expect(find.text('Pumped · 80 ml'), findsOneWidget);
      expect(find.text('Fed as breast milk · 150 ml'), findsOneWidget);
    });

    testWidgets('pumped vs fed goes with pumping switched off', (tester) async {
      await pumpInsights(
        tester,
        feeds: mixed,
        pumps: pumpedWeek,
        pumpingShown: false,
      );
      await scrollTo(tester, find.text('Bottles by milk'));
      expect(find.text('Pumped vs fed'), findsNothing);
    });

    testWidgets('and neither shows without bottles or pumping', (tester) async {
      await pumpInsights(
        tester,
        feeds: [
          FeedingEvent(
            id: 'b',
            type: FeedingType.breast,
            startTime: DateTime(today.year, today.month, today.day, 8),
            durationMinutes: 20,
          ),
        ],
      );
      expect(find.text('Bottles by milk'), findsNothing);
      expect(find.text('Pumped vs fed'), findsNothing);
    });

    for (final (size, scale) in [
      (const Size(320, 700), 1.0),
      (const Size(390, 844), 2.0),
    ]) {
      testWidgets('fits ${size.width.toInt()} wide at ${scale}x text', (
        tester,
      ) async {
        await pumpInsights(
          tester,
          feeds: [...mixed, bottle(60, null, daysAgo: 3)],
          pumps: pumpedWeek,
          size: size,
          textScale: scale,
        );
        await scrollTo(tester, find.text('Pumped vs fed'));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Day'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('the Milk labels read as they do elsewhere', () {
    expect(milkLabel(MilkKind.formula), 'Formula');
    expect(milkLabel(null), 'Not recorded');
    expect(UnitSystem.metric.isMetric, isTrue);
  });
}
