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
import 'package:baby_app/features/home/home_prefs.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// The "Last pumped" row on the Home status card.
///
/// Opt-in, like the solids row above it, and that is the part worth pinning:
/// a household that has never pumped should not carry an empty row for it,
/// and one that has switched pumping off has already said it does not want
/// the subject on Home at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  final feeds = [
    FeedingEvent(
      id: 'f1',
      type: FeedingType.bottle,
      startTime: now.subtract(const Duration(hours: 2)),
      amountMl: 150,
    ),
  ];
  final diapers = [
    DiaperEvent(
      id: 'd1',
      type: DiaperType.wet,
      time: now.subtract(const Duration(minutes: 40)),
    ),
  ];
  final pumps = [
    PumpingEvent(
      id: 'p1',
      time: now.subtract(const Duration(minutes: 25)),
      durationMinutes: 15,
      amountMl: 90,
    ),
    PumpingEvent(
      id: 'p2',
      time: now.subtract(const Duration(hours: 5)),
      amountMl: 60,
    ),
  ];

  Future<void> pumpCard(
    WidgetTester tester, {
    List<PumpingEvent> pumping = const [],
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'reminder_mode': 'fixedInterval',
      'unit_system': 'metric',
      ...prefs,
    });
    final stored = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          // Signed out: every repository provider is null, so the only data
          // in play is what is overridden below.
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          recentFeedingsProvider.overrideWith((ref) => Stream.value(feeds)),
          recentDiapersProvider.overrideWith((ref) => Stream.value(diapers)),
          recentPumpingProvider.overrideWith((ref) => Stream.value(pumping)),
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

  testWidgets('shows the most recent session', (tester) async {
    await pumpCard(tester, pumping: pumps);

    expect(find.text('Last pumped'), findsOneWidget);
    expect(find.text('25 min ago'), findsOneWidget);
    // The newer session, not the 60 ml one five hours back.
    expect(find.textContaining('15 min · 90 ml'), findsOneWidget);
  });

  testWidgets('stays away until something has been pumped', (tester) async {
    // A household that never pumps would otherwise carry a permanently empty
    // row, the same clutter the solids row avoids.
    await pumpCard(tester);

    expect(find.text('Last pumped'), findsNothing);
    expect(find.text('Last fed'), findsOneWidget);
    expect(find.text('Last diaper changed'), findsOneWidget);
  });

  testWidgets('and goes away when pumping is switched off', (tester) async {
    // Turning the pumping action off says pumping is not part of this
    // household's day. Leaving its history on Home would contradict that.
    await pumpCard(
      tester,
      pumping: pumps,
      prefs: {'show_pumping_action': false},
    );

    expect(find.text('Last pumped'), findsNothing);
  });

  testWidgets('gets its own card in the separate layout', (tester) async {
    await pumpCard(
      tester,
      pumping: pumps,
      prefs: {'home_layout': HomeLayout.separate.name},
    );

    expect(find.byType(Card), findsNWidgets(3));
    expect(find.text('Last pumped'), findsOneWidget);
  });
}
