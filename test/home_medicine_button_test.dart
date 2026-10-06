import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/layout/app_bar_room.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/medication_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/baby_switcher.dart';
import 'package:baby_app/features/home/home_screen.dart';
import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/medication/medicine_sheet.dart';

/// Medicine on Home (#37): a button in the top-left corner, not a row of
/// the status card, and only while medicine is being given.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baby = Baby(
    id: 'baby1',
    name: 'Jonathan',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  MedicationEvent dose(Duration ago, {int? wait}) => MedicationEvent(
    id: 'm$ago',
    time: DateTime.now().subtract(ago),
    name: 'Tylenol',
    dose: 2.5,
    unit: DoseUnit.ml,
    waitHours: wait,
    byName: 'Alex',
  );

  Future<void> pumpHome(
    WidgetTester tester, {
    List<MedicationEvent> meds = const [],
    Map<String, Object> prefs = const {},
    Size size = const Size(390, 844),
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric', ...prefs});
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
          recentFeedingsProvider.overrideWith((ref) => Stream.value([])),
          recentDiapersProvider.overrideWith((ref) => Stream.value([])),
          recentPumpingProvider.overrideWith((ref) => Stream.value([])),
          recentMedsProvider.overrideWith((ref) => Stream.value(meds)),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final inBar = find.descendant(
    of: find.byType(AppBar),
    matching: find.byTooltip('Medicine'),
  );

  testWidgets('is not on the status card any more', (tester) async {
    await pumpHome(tester, meds: [dose(const Duration(hours: 3))]);
    expect(
      find.descendant(
        of: find.byType(HomeStatusCard),
        matching: find.text('MEDICINE'),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Log medicine'), findsNothing);
  });

  testWidgets('sits in the top-left corner while medicine is being given', (
    tester,
  ) async {
    await pumpHome(tester, meds: [dose(const Duration(hours: 3))]);
    expect(inBar, findsOneWidget);
    // Left of the baby's name, which keeps its room.
    expect(
      tester.getRect(inBar).right,
      lessThanOrEqualTo(tester.getRect(find.byType(BabySwitcher)).left),
    );
    expect(
      tester.getRect(find.byType(BabySwitcher)).width,
      greaterThan(AppBarRoom.nameFloor),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the medicine sheet, which logs a dose', (tester) async {
    await pumpHome(tester, meds: [dose(const Duration(hours: 2), wait: 6)]);
    await tester.tap(inBar);
    await tester.pumpAndSettle();

    expect(find.text('Tylenol · 2.5 ml'), findsOneWidget);
    expect(
      find.textContaining('by Alex · 1 in the last 24 hr'),
      findsOneWidget,
    );
    expect(find.textContaining('Next Tylenol in '), findsOneWidget);

    await tester.tap(find.text('Log medicine'));
    await tester.pumpAndSettle();
    expect(find.text('Dose (optional)'), findsOneWidget);
  });

  testWidgets('goes once a week has passed since the last dose', (
    tester,
  ) async {
    // The baby is better: nothing left on Home to say they ever were not.
    await pumpHome(tester, meds: [dose(const Duration(days: 8))]);
    expect(inBar, findsNothing);
  });

  testWidgets('and is never there for a household not giving any', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(inBar, findsNothing);
  });

  testWidgets('switched on, it stays regardless', (tester) async {
    await pumpHome(
      tester,
      meds: [dose(const Duration(days: 30))],
      prefs: {'show_medication': true},
    );
    expect(inBar, findsOneWidget);
  });

  testWidgets('fits beside the clock on a tablet', (tester) async {
    await pumpHome(
      tester,
      meds: [dose(const Duration(hours: 3))],
      size: const Size(834, 1194),
    );
    expect(tester.takeException(), isNull);
    expect(inBar, findsOneWidget);
  });

  group('medicineButtonShown', () {
    final now = DateTime(2026, 10, 6, 12);
    MedicationEvent at(Duration ago) =>
        MedicationEvent(id: 'x', time: now.subtract(ago), name: 'Tylenol');

    test('for a week after the last dose', () {
      bool shown(Duration ago) =>
          medicineButtonShown(doses: [at(ago)], switchedOn: false, now: now);
      expect(shown(const Duration(days: 6, hours: 23)), isTrue);
      expect(shown(const Duration(days: 7)), isFalse);
    });

    test('always when switched on', () {
      expect(
        medicineButtonShown(doses: const [], switchedOn: true, now: now),
        isTrue,
      );
    });
  });
}
