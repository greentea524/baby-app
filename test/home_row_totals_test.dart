import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// Today's totals on Home's feed and pump rows, beside the clock time: what
/// the "Today" line under the card used to say on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mid-afternoon, so "today" has room either side of every event.
  final now = DateTime(2026, 11, 6, 15);
  DateTime ago(int hours) => now.subtract(Duration(hours: hours));

  FeedingEvent bottle(String id, DateTime at, double ml) => FeedingEvent(
    id: id,
    type: FeedingType.bottle,
    startTime: at,
    amountMl: ml,
  );
  FeedingEvent breast(String id, DateTime at, int minutes) => FeedingEvent(
    id: id,
    type: FeedingType.breast,
    startTime: at,
    durationMinutes: minutes,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    List<FeedingEvent> feeds = const [],
    List<PumpingEvent> pumps = const [],
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          recentFeedingsProvider.overrideWith((ref) => Stream.value(feeds)),
          recentDiapersProvider.overrideWith((ref) => Stream.value(const [])),
          recentPumpingProvider.overrideWith((ref) => Stream.value(pumps)),
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

  String totalOn(WidgetTester tester) => tester
      .widgetList<TodayTotal>(find.byType(TodayTotal))
      .map((t) => t.parts.join(' · ').replaceAll(' ', ' '))
      .join(' | ');

  testWidgets('the feed row adds up today\'s bottles', (tester) async {
    await pumpCard(
      tester,
      feeds: [
        bottle('f3', ago(1), 120),
        bottle('f2', ago(4), 150),
        bottle('f1', ago(8), 90),
        // Last night's does not count.
        bottle('f0', ago(20), 200),
      ],
    );
    expect(totalOn(tester), '360 ml');
    expect(find.textContaining('Today: '), findsOneWidget);
  });

  testWidgets('and the minutes at the breast beside them', (tester) async {
    await pumpCard(
      tester,
      feeds: [breast('f2', ago(1), 15), bottle('f1', ago(4), 120)],
    );
    expect(totalOn(tester), '120 ml · 15 min breast');
  });

  testWidgets('or only the breast, when that is all', (tester) async {
    await pumpCard(tester, feeds: [breast('f1', ago(1), 20)]);
    expect(totalOn(tester), '20 min breast');
  });

  testWidgets('says nothing before anything today', (tester) async {
    await pumpCard(tester, feeds: [bottle('f0', ago(20), 200)]);
    expect(find.byType(TodayTotal), findsNothing);
  });

  testWidgets('the pump row adds up today\'s sessions', (tester) async {
    await pumpCard(
      tester,
      pumps: [
        PumpingEvent(id: 'p2', time: ago(1), amountMl: 130),
        PumpingEvent(id: 'p1', time: ago(5), amountMl: 110),
        PumpingEvent(id: 'p0', time: ago(18), amountMl: 150),
      ],
    );
    expect(totalOn(tester), '240 ml');
  });
}
