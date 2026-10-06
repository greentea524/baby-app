import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/medication_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/home/nursery_screen.dart';

/// Nursery mode's medicine button, and the sheet it opens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 6, 14);
  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  MedicationEvent dose(
    String id,
    String name,
    Duration ago, {
    double? amount,
    int? wait,
    String? by,
  }) => MedicationEvent(
    id: id,
    time: now.subtract(ago),
    name: name,
    dose: amount,
    unit: amount == null ? null : DoseUnit.ml,
    waitHours: wait,
    byName: by,
  );

  Future<void> pumpNursery(
    WidgetTester tester, {
    List<MedicationEvent> meds = const [],
    Map<String, Object> prefs = const {},
    Size size = const Size(834, 1194),
  }) async {
    SharedPreferences.setMockInitialValues({
      'display_mode': 'nursery',
      'unit_system': 'metric',
      ...prefs,
    });
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
        child: MaterialApp(home: NurseryScreen(now: now)),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool waiting(WidgetTester tester) => tester
      .widget<Badge>(find.byKey(const ValueKey('medicine-waiting')))
      .isLabelVisible;

  testWidgets('is not there for a household that has never given any', (
    tester,
  ) async {
    await pumpNursery(tester);
    expect(find.byTooltip('Medicine'), findsNothing);
  });

  testWidgets('is there once switched on, to log the first dose', (
    tester,
  ) async {
    await pumpNursery(tester, prefs: {'show_medication': true});
    await tester.tap(find.byTooltip('Medicine'));
    await tester.pumpAndSettle();
    expect(find.text('No medicine logged yet.'), findsOneWidget);

    // The log sheet in place of this one, not stacked on it.
    await tester.tap(find.text('Log medicine'));
    await tester.pumpAndSettle();
    expect(find.text('No medicine logged yet.'), findsNothing);
    expect(find.text('Dose (optional)'), findsOneWidget);
  });

  testWidgets('lists each medicine by its last dose, newest first', (
    tester,
  ) async {
    await pumpNursery(
      tester,
      meds: [
        dose(
          't2',
          'Tylenol',
          const Duration(hours: 2),
          amount: 2.5,
          wait: 6,
          by: 'Alex',
        ),
        dose('i1', 'Ibuprofen', const Duration(hours: 30), amount: 5),
        dose('t1', 'tylenol ', const Duration(hours: 9), amount: 2.5),
      ],
    );
    // A wait is running, so the button says so before it is opened.
    expect(waiting(tester), isTrue);

    await tester.tap(find.byTooltip('Medicine'));
    await tester.pumpAndSettle();

    final tylenol = find.text('Tylenol · 2.5 ml');
    final ibuprofen = find.text('Ibuprofen · 5 ml');
    expect(tylenol, findsOneWidget);
    expect(ibuprofen, findsOneWidget);
    expect(
      tester.getRect(tylenol).top,
      lessThan(tester.getRect(ibuprofen).top),
    );

    expect(find.text('2h ago'), findsOneWidget);
    // Both Tylenol doses count, whatever case they were typed in.
    expect(
      find.textContaining('by Alex · 2 in the last 24 hr'),
      findsOneWidget,
    );
    expect(find.textContaining('0 in the last 24 hr'), findsOneWidget);

    // The countdown for the one still inside its wait, and only that one.
    final chip = tester.widget<DueChip>(find.byType(DueChip));
    expect(chip.text, startsWith('Next Tylenol in 4h'));
    expect(chip.remaining, closeTo(4 / 6, 0.01));
  });

  testWidgets('with no dot once every wait is over', (tester) async {
    await pumpNursery(
      tester,
      meds: [dose('t1', 'Tylenol', const Duration(hours: 7), wait: 6)],
    );
    expect(waiting(tester), isFalse);

    await tester.tap(find.byTooltip('Medicine'));
    await tester.pumpAndSettle();
    expect(find.byType(DueChip), findsNothing);
  });

  testWidgets('fits the header on a phone', (tester) async {
    await pumpNursery(
      tester,
      size: const Size(320, 640),
      meds: [dose('t1', 'Tylenol', const Duration(hours: 2), wait: 6)],
    );
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Medicine'), findsOneWidget);
    expect(find.byTooltip('Leave nursery mode'), findsOneWidget);
  });
}
