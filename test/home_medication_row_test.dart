import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/medication_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// The "Last medicine" row on Home (#37).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 6, 14);

  Future<void> pumpCard(
    WidgetTester tester, {
    List<MedicationEvent> meds = const [],
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric', ...prefs});
    final stored = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          recentFeedingsProvider.overrideWith((ref) => Stream.value([])),
          recentDiapersProvider.overrideWith((ref) => Stream.value([])),
          recentPumpingProvider.overrideWith((ref) => Stream.value([])),
          recentMedsProvider.overrideWith((ref) => Stream.value(meds)),
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

  testWidgets('stays away until switched on or a dose is logged', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('Last medicine'), findsNothing);
  });

  testWidgets('switched on, it is there to log the first dose from', (
    tester,
  ) async {
    await pumpCard(tester, prefs: {'show_medication': true});
    expect(find.text('Last medicine'), findsOneWidget);
    expect(find.text('None yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Log medicine'));
    await tester.pumpAndSettle();
    expect(find.text('Log medicine'), findsWidgets);
  });

  testWidgets('says what was given, how long ago, and by whom', (tester) async {
    // Shown once there is a dose, switch or no switch.
    await pumpCard(
      tester,
      meds: [
        MedicationEvent(
          id: 'm1',
          time: now.subtract(const Duration(hours: 3)),
          name: 'Tylenol',
          dose: 2.5,
          unit: DoseUnit.ml,
          byName: 'Alex',
        ),
      ],
    );
    expect(find.text('Last medicine'), findsOneWidget);
    expect(find.text('3 hr ago'), findsOneWidget);
    expect(find.textContaining('Tylenol 2.5 ml · by Alex'), findsOneWidget);
  });
}
