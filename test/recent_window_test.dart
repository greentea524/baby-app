import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/activity/activity_tile.dart';
import 'package:baby_app/features/home/home_screen.dart';
import 'package:baby_app/features/home/recent_activity_list.dart';

/// How far back Home's recent list reaches.
///
/// It was the last 50 of each kind merged, which on a busy week ran to
/// hundreds of rows — a scroll nobody reaches the end of, when the question
/// it answers is what has been happening lately.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the window', () {
    test('is today and the two days before it', () {
      final now = DateTime(2026, 8, 24, 15, 30);
      expect(recentActivityCutoff(now), DateTime(2026, 8, 22));
    });

    test('starts at midnight, not at this time of day', () {
      // Counted in whole days so the list does not change under the reader:
      // at 72 hours a 4am feed would drop off at 4am, which looks like data
      // going missing rather than a window moving.
      final morning = recentActivityCutoff(DateTime(2026, 8, 24, 4));
      final evening = recentActivityCutoff(DateTime(2026, 8, 24, 23, 59));
      expect(morning, evening);
      expect(morning.hour, 0);
    });

    test('crosses a month boundary without arithmetic of its own', () {
      expect(
        recentActivityCutoff(DateTime(2026, 9, 1, 8)),
        DateTime(2026, 8, 30),
      );
    });
  });

  group('on Home', () {
    final baby = Baby(
      id: 'baby1',
      name: 'Ada',
      birthDate: DateTime(2026, 2, 1),
      ownerUid: 'alice',
      members: const {'alice': CaregiverRole.owner},
    );
    final now = DateTime.now();

    Future<void> pumpHome(
      WidgetTester tester, {
      required List<FeedingEvent> feeds,
      List<DiaperEvent> diapers = const [],
    }) async {
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
            recentFeedingsProvider.overrideWith((ref) => Stream.value(feeds)),
            recentDiapersProvider.overrideWith((ref) => Stream.value(diapers)),
            recentPumpingProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    FeedingEvent feedAt(String id, Duration ago) => FeedingEvent(
      id: id,
      type: FeedingType.bottle,
      startTime: now.subtract(ago),
      amountMl: 120,
    );

    testWidgets('drops what is older than the window', (tester) async {
      await pumpHome(
        tester,
        feeds: [
          feedAt('today', const Duration(hours: 1)),
          feedAt('yesterday', const Duration(days: 1)),
          // Comfortably outside on any hour of the day.
          feedAt('lastweek', const Duration(days: 8)),
        ],
      );

      // Two rows, not three: the week-old feed is a day to look up on the
      // timeline, not a row to scroll past on Home.
      expect(find.byType(ActivityTile), findsNWidgets(2));
    });

    testWidgets('keeps the far edge of the window, and no more', (
      tester,
    ) async {
      // Either side of the boundary by five minutes. Counting rows spread
      // across the window would not do it: the list is lazy, so anything
      // below the fold is simply not built.
      final windowStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 2));

      await pumpHome(
        tester,
        feeds: [
          feedAt('today', const Duration(hours: 1)),
          FeedingEvent(
            id: 'just-inside',
            type: FeedingType.breast,
            startTime: windowStart.add(const Duration(minutes: 5)),
            durationMinutes: 15,
          ),
          FeedingEvent(
            id: 'just-outside',
            type: FeedingType.breast,
            startTime: windowStart.subtract(const Duration(minutes: 5)),
            durationMinutes: 15,
          ),
        ],
      );

      expect(find.byType(ActivityTile), findsNWidgets(2));
    });

    testWidgets('says the days were quiet rather than showing nothing', (
      tester,
    ) async {
      // There *is* history — it is just all older than the window, which is
      // a different thing from a baby with no records at all.
      await pumpHome(tester, feeds: [feedAt('old', const Duration(days: 9))]);

      expect(find.byType(ActivityTile), findsNothing);
      expect(find.text('Nothing logged in the last 3 days.'), findsOneWidget);
      expect(find.text('No activity yet.'), findsNothing);
    });

    testWidgets('still says so plainly when there is no history at all', (
      tester,
    ) async {
      await pumpHome(tester, feeds: const []);
      expect(find.text('No activity yet.'), findsOneWidget);
    });
  });
}
