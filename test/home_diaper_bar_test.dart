import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/insights/diaper_mix_bar.dart';

/// Today's diapers by what was in them, on Home's diaper row: the Insights
/// day view's bar, where "has there been a dirty one yet" gets asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 16, 15);
  DiaperEvent change(String id, DiaperType type, Duration ago) =>
      DiaperEvent(id: id, type: type, time: now.subtract(ago));

  Future<void> pumpCard(WidgetTester tester, List<DiaperEvent> diapers) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          recentFeedingsProvider.overrideWith((ref) => Stream.value([])),
          recentDiapersProvider.overrideWith((ref) => Stream.value(diapers)),
          recentPumpingProvider.overrideWith((ref) => Stream.value([])),
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

  final bar = find.byKey(const ValueKey('home-diaper-mix'));

  testWidgets('counts today\'s changes by what was in them', (tester) async {
    await pumpCard(tester, [
      change('a', DiaperType.wet, const Duration(hours: 1)),
      change('b', DiaperType.wet, const Duration(hours: 4)),
      change('c', DiaperType.dirty, const Duration(hours: 6)),
      // Yesterday: not today's.
      change('d', DiaperType.both, const Duration(hours: 20)),
    ]);
    expect(bar, findsOneWidget);
    expect(tester.widget<DiaperMixBar>(bar).mix, (wet: 2, dirty: 1, both: 0));
    expect(find.text('2 Wet'), findsOneWidget);
    expect(find.text('1 Dirty'), findsOneWidget);
    expect(find.text('0 Both'), findsOneWidget);
    // With a dirty one today the counts say it; no line repeats it.
    expect(find.textContaining('dirty diaper'), findsNothing);
    expect(find.textContaining('None yet today'), findsNothing);
  });

  testWidgets('and says how long since the last dirty one, when not today', (
    tester,
  ) async {
    await pumpCard(tester, [
      change('a', DiaperType.wet, const Duration(hours: 1)),
      change('b', DiaperType.both, const Duration(hours: 20)),
    ]);
    expect(
      find.textContaining('None yet today — the last was'),
      findsOneWidget,
    );
  });

  testWidgets('is thinner than the Insights one', (tester) async {
    await pumpCard(tester, [
      change('a', DiaperType.wet, const Duration(hours: 1)),
    ]);
    expect(tester.widget<DiaperMixBar>(bar).compact, isTrue);
  });

  testWidgets('and is not there before the first change ever', (tester) async {
    await pumpCard(tester, const []);
    expect(find.text('No changes yet'), findsOneWidget);
    expect(bar, findsNothing);
  });
}
