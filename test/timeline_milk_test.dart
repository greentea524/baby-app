import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/milk_kind.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/insights/milk_mix.dart';
import 'package:baby_app/features/timeline/timeline_screen.dart';

/// The day's milk on the Timeline's stat chips: what was in the bottles, and
/// how pumping set against the breast milk fed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final day = DateTime.now();
  DateTime at(int hour) => DateTime(day.year, day.month, day.day, hour);

  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  FeedingEvent bottle(double ml, MilkKind? milk, int hour) => FeedingEvent(
    id: 'f$hour',
    type: FeedingType.bottle,
    startTime: at(hour),
    amountMl: ml,
    milk: milk,
  );

  Future<void> pumpTimeline(
    WidgetTester tester, {
    required List<FeedingEvent> feeds,
    List<PumpingEvent> pumps = const [],
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
          feedingsForDayProvider.overrideWith((ref) => Stream.value(feeds)),
          diapersForDayProvider.overrideWith((ref) => Stream.value([])),
          pumpingForDayProvider.overrideWith((ref) => Stream.value(pumps)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: const TimelineScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the bottle chip says what was in the bottles', (tester) async {
    await pumpTimeline(
      tester,
      feeds: [
        bottle(120, MilkKind.expressed, 6),
        bottle(120, MilkKind.expressed, 10),
        bottle(60, MilkKind.formula, 14),
      ],
    );
    expect(find.text('300 ml'), findsOneWidget);
    expect(find.text('80% breast milk · 20% formula'), findsOneWidget);
  });

  testWidgets('and the pump chip, how pumping kept up', (tester) async {
    await pumpTimeline(
      tester,
      feeds: [
        bottle(120, MilkKind.expressed, 6),
        bottle(120, MilkKind.expressed, 10),
      ],
      pumps: [PumpingEvent(id: 'p', time: at(8), amountMl: 264)],
    );
    expect(find.text('all breast milk'), findsOneWidget);
    expect(find.text('1x · 110% of breast milk fed'), findsOneWidget);
  });

  testWidgets('with no breast milk fed, there is nothing to measure', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      feeds: [bottle(90, MilkKind.formula, 6)],
      pumps: [PumpingEvent(id: 'p', time: at(8), amountMl: 100)],
    );
    expect(find.text('all formula'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
  });

  testWidgets('and bottles with no milk recorded say nothing of it', (
    tester,
  ) async {
    // An old day: the chip is as it always was, not "0% breast milk".
    await pumpTimeline(tester, feeds: [bottle(120, null, 6)]);
    // The chip, and the feed's own row in the list.
    expect(find.text('120 ml'), findsWidgets);
    expect(find.textContaining('breast milk'), findsNothing);
  });

  testWidgets('fits a small phone at 200% text', (tester) async {
    await pumpTimeline(
      tester,
      feeds: [
        bottle(120, MilkKind.expressed, 6),
        bottle(90, MilkKind.formula, 10),
        bottle(60, MilkKind.wholeMilk, 14),
      ],
      pumps: [PumpingEvent(id: 'p', time: at(8), amountMl: 100)],
      size: const Size(320, 640),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
  });

  group('the shares', () {
    test('largest first, of the bottles whose milk is known', () {
      expect(
        milkShares(
          const MilkMix(formulaMl: 300, breastMilkMl: 100, unknownMl: 999),
        ),
        '75% formula · 25% breast milk',
      );
    });

    test('one milk is said as all of it', () {
      expect(milkShares(const MilkMix(wholeMilkMl: 150)), 'all whole milk');
    });

    test('and nothing is said when none is known', () {
      expect(milkShares(const MilkMix(unknownMl: 120)), isNull);
      expect(milkShares(const MilkMix()), isNull);
    });
  });
}
