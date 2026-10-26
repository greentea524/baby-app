import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// Each Home row says which of the day's it is showing: "FEED #3", the
/// third feed today; "DIAPER #5", the fifth change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 26, 15);
  DateTime at(int hour, {int day = 26}) => DateTime(2026, 10, day, hour);

  FeedingEvent feed(String id, FeedingType type, DateTime time) => FeedingEvent(
    id: id,
    type: type,
    startTime: time,
    amountMl: type == FeedingType.bottle ? 120 : null,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    List<FeedingEvent> feeds = const [],
    List<DiaperEvent> diapers = const [],
    List<PumpingEvent> pumps = const [],
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          // Newest first, as the repositories hand them back.
          recentFeedingsProvider.overrideWith(
            (ref) => Stream.value(
              [...feeds]..sort((a, b) => b.startTime.compareTo(a.startTime)),
            ),
          ),
          recentDiapersProvider.overrideWith(
            (ref) => Stream.value(
              [...diapers]..sort((a, b) => b.time.compareTo(a.time)),
            ),
          ),
          recentPumpingProvider.overrideWith(
            (ref) => Stream.value(
              [...pumps]..sort((a, b) => b.time.compareTo(a.time)),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: HomeStatusCard(now: now)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('counts every milk feed today on the label', (tester) async {
    await pumpCard(
      tester,
      feeds: [
        // Yesterday's: a day that is over.
        feed('y', FeedingType.bottle, at(22, day: 25)),
        feed('a', FeedingType.bottle, at(7)),
        feed('b', FeedingType.breast, at(9)),
        // Solids have a row, and a count, of their own.
        feed('s', FeedingType.solids, at(11)),
        feed('c', FeedingType.bottle, at(12)),
      ],
    );
    expect(find.text('FEED\u00a0#3'), findsOneWidget);
    expect(find.text('SOLIDS\u00a0#1'), findsOneWidget);
    // The headline is what it was.
    expect(find.text('Bottle · 120\u00a0ml'), findsOneWidget);
  });

  testWidgets('has no number for last night\'s feed', (tester) async {
    await pumpCard(
      tester,
      feeds: [feed('y', FeedingType.bottle, at(23, day: 25))],
    );
    expect(find.text('FEED'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);
  });

  testWidgets('numbers the diaper change and the pump', (tester) async {
    await pumpCard(
      tester,
      diapers: [
        for (final (i, h) in [6, 9, 11, 13, 14].indexed)
          DiaperEvent(id: 'd$i', type: DiaperType.wet, time: at(h)),
        DiaperEvent(id: 'y', type: DiaperType.wet, time: at(23, day: 25)),
      ],
      pumps: [
        for (final (i, h) in [5, 10].indexed)
          PumpingEvent(id: 'p$i', time: at(h), amountMl: 90),
      ],
    );
    expect(find.text('DIAPER #5'), findsOneWidget);
    expect(find.text('PUMP #2'), findsOneWidget);
  });

  test('numberToday counts up to and including the one shown', () {
    final times = [at(6), at(9), at(12)];
    expect(numberToday(times, at(9), (t) => t, now), 2);
    expect(numberToday(times, at(12), (t) => t, now), 3);
    expect(numberToday(times, at(23, day: 25), (t) => t, now), isNull);
  });
}
