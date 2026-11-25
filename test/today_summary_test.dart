import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_screen.dart';
import 'package:baby_app/features/home/today_summary.dart';
import 'package:baby_app/features/insights/day_timeline_strip.dart';
import 'package:baby_app/features/insights/diaper_mix_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  test('calendarDay normalizes times on the same local date', () {
    final morning = calendarDay(DateTime(2026, 8, 24, 6, 15));
    final night = calendarDay(DateTime(2026, 8, 24, 23, 59, 59));
    final next = calendarDay(DateTime(2026, 8, 25, 0, 0, 1));

    expect(morning, DateTime(2026, 8, 24));
    expect(morning, night);
    expect(morning, isNot(next));
  });

  test(
    'todayEventsProvider and todayStatsProvider reset across midnight without new stream events',
    () {
      final day1Time = DateTime(2026, 8, 24, 23, 0);
      final day1 = calendarDay(DateTime(2026, 8, 24, 23, 55));
      final day2 = calendarDay(DateTime(2026, 8, 25, 0, 5));

      final container = ProviderContainer(
        overrides: [
          recentFeedingsProvider.overrideWithValue(
            AsyncData([
              FeedingEvent(
                id: 'f1',
                type: FeedingType.bottle,
                startTime: day1Time,
                amountMl: 150,
              ),
            ]),
          ),
          recentDiapersProvider.overrideWithValue(
            AsyncData([
              DiaperEvent(id: 'd1', type: DiaperType.dirty, time: day1Time),
            ]),
          ),
          recentPumpingProvider.overrideWithValue(
            AsyncData([PumpingEvent(id: 'p1', time: day1Time, amountMl: 90)]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final day1Events = container.read(todayEventsProvider(day1));
      expect(day1Events.feedings, hasLength(1));
      expect(day1Events.diapers, hasLength(1));
      expect(day1Events.pumps, hasLength(1));

      final day1Stats = container.read(todayStatsProvider(day1));
      expect(day1Stats.feedCount, 1);
      expect(day1Stats.bottleMl, 150);
      expect(day1Stats.diaperCount, 1);
      expect(day1Stats.pumpCount, 1);
      expect(day1Stats.pumpedMl, 90);

      final day2Events = container.read(todayEventsProvider(day2));
      expect(day2Events.feedings, isEmpty);
      expect(day2Events.diapers, isEmpty);
      expect(day2Events.pumps, isEmpty);

      final day2Stats = container.read(todayStatsProvider(day2));
      expect(day2Stats.feedCount, 0);
      expect(day2Stats.bottleMl, 0);
      expect(day2Stats.diaperCount, 0);
      expect(day2Stats.pumpCount, 0);
      expect(day2Stats.pumpedMl, 0);
    },
  );

  testWidgets('Home Today charts clear past midnight with no stream write', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'home_activity_scope': 'today'});
    final stored = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(834, 1194);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final loggedAt = DateTime(2026, 8, 24, 23, 0);
    final beforeMidnight = DateTime(2026, 8, 24, 23, 55);
    final afterMidnight = DateTime(2026, 8, 25, 0, 5);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(stored),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
        recentFeedingsProvider.overrideWith(
          (ref) => Stream.value([
            FeedingEvent(
              id: 'f1',
              type: FeedingType.bottle,
              startTime: loggedAt,
              amountMl: 150,
            ),
          ]),
        ),
        recentDiapersProvider.overrideWith(
          (ref) => Stream.value([
            DiaperEvent(id: 'd1', type: DiaperType.dirty, time: loggedAt),
          ]),
        ),
        recentPumpingProvider.overrideWith(
          (ref) => Stream.value([
            PumpingEvent(id: 'p1', time: loggedAt, amountMl: 90),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    Widget buildHome(DateTime clock) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: HomeScreen(now: clock)),
    );

    await tester.pumpWidget(buildHome(beforeMidnight));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(DayTimelineStrip),
        matching: find.text('1 feed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DayTimelineStrip),
        matching: find.text('1 diaper'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DayTimelineStrip),
        matching: find.text('1 pump'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DiaperMixBar),
        matching: find.text('1 dirty diaper today.'),
      ),
      findsOneWidget,
    );

    // Roll Home's clock past midnight without any new Firestore stream events.
    await tester.pumpWidget(buildHome(afterMidnight));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(DayTimelineStrip),
        matching: find.text('Nothing logged on this day.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DiaperMixBar),
        matching: find.text('None yet today — the last was 1h 5m ago.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('live HomeScreen refreshes on resume and disposes cleanly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'home_activity_scope': 'today'});
    final stored = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(834, 1194);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
          recentFeedingsProvider.overrideWith((ref) => Stream.value(const [])),
          recentDiapersProvider.overrideWith((ref) => Stream.value(const [])),
          recentPumpingProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(tester.takeException(), isNull);
  });
}
