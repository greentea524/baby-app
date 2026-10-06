import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/medication_event.dart';
import 'package:baby_app/data/repositories/medication_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/medication/medication_format.dart';
import 'package:baby_app/features/medication/medication_quick_log.dart';

/// Logging medicine (#37): what is recorded, how it is said, and the sheet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  MedicationEvent dose(
    String name, {
    required int hoursAgo,
    double? dose,
    DoseUnit? unit,
    String? by,
    String? createdBy,
    String id = '',
    int? wait,
  }) => MedicationEvent(
    id: id.isEmpty ? '$name-$hoursAgo' : id,
    time: now.subtract(Duration(hours: hoursAgo)),
    name: name,
    dose: dose,
    unit: unit,
    byName: by,
    createdBy: createdBy,
    waitHours: wait,
  );

  group('how a dose is said', () {
    test('in its unit, singular or plural', () {
      expect(DoseUnit.ml.amount(2.5), '2.5 ml');
      expect(DoseUnit.tablet.amount(1), '1 tablet');
      expect(DoseUnit.tablet.amount(2), '2 tablets');
      expect(DoseUnit.drops.amount(3), '3 drops');
    });

    test('with who gave it: you, or their name', () {
      final mine = dose('Tylenol', hoursAgo: 1, createdBy: 'me', by: 'Sam');
      final theirs = dose(
        'Tylenol',
        hoursAgo: 1,
        createdBy: 'them',
        by: 'Alex',
      );
      expect(MedicationFormat.givenBy(mine, 'me'), 'you');
      expect(MedicationFormat.givenBy(theirs, 'me'), 'Alex');
      expect(
        MedicationFormat.details(
          dose(
            'Tylenol',
            hoursAgo: 1,
            dose: 2.5,
            unit: DoseUnit.ml,
            by: 'Alex',
          ),
          'me',
        ),
        '2.5 ml · by Alex',
      );
    });

    test('counted per medicine for a day', () {
      expect(
        dosesByMedicine([
          dose('Tylenol', hoursAgo: 1),
          dose('Ibuprofen', hoursAgo: 2),
          dose('Tylenol', hoursAgo: 5),
        ]),
        'Tylenol ×2 · Ibuprofen',
      );
    });
  });

  group('the medicines offered again', () {
    test('most recent first, one each, whatever the case', () {
      final recent = recentMedicines([
        dose('Tylenol', hoursAgo: 9, dose: 2.5),
        dose('Ibuprofen', hoursAgo: 4),
        dose('tylenol ', hoursAgo: 1, dose: 3),
      ]);
      expect(recent.map((m) => m.name), ['tylenol ', 'Ibuprofen']);
      // With the dose it was last given at.
      expect(recent.first.dose, 3);
    });

    test('at most four', () {
      expect(
        recentMedicines([
          for (var i = 0; i < 6; i++) dose('Med $i', hoursAgo: i),
        ]).length,
        4,
      );
    });
  });

  group('the sheet', () {
    late _RecordingMeds meds;

    Future<void> openSheet(
      WidgetTester tester, {
      List<MedicationEvent> history = const [],
      MedicationEvent? existing,
      Size size = const Size(390, 900),
      double textScale = 1,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      meds = _RecordingMeds();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            medicationRepositoryProvider.overrideWithValue(meds),
            recentMedsProvider.overrideWith((ref) => Stream.value(history)),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () =>
                          showMedicationQuickLog(context, existing: existing),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder save() => find.widgetWithText(FilledButton, 'Save');
    bool canSave(WidgetTester tester) =>
        tester.widget<FilledButton>(save()).onPressed != null;
    Future<void> tapIn(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('logs a medicine, its dose and unit', (tester) async {
      await openSheet(tester);
      expect(canSave(tester), isFalse, reason: 'needs a name first');

      await tester.enterText(
        find.widgetWithText(TextField, 'Medicine'),
        'Tylenol',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dose (optional)'),
        '2.5',
      );
      await tapIn(tester, find.widgetWithText(ChoiceChip, 'ml'));
      await tapIn(tester, save());

      final saved = meds.added.single;
      expect(saved.name, 'Tylenol');
      expect(saved.dose, 2.5);
      expect(saved.unit, DoseUnit.ml);
    });

    testWidgets('without a dose too', (tester) async {
      await openSheet(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Medicine'),
        'Gripe water',
      );
      await tester.pump();
      await tapIn(tester, save());
      expect(meds.added.single.dose, isNull);
      expect(meds.added.single.unit, isNull);
    });

    testWidgets('but not a dose of nothing', (tester) async {
      await openSheet(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Medicine'),
        'Tylenol',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dose (optional)'),
        '0',
      );
      await tester.pump();
      expect(canSave(tester), isFalse);
      expect(find.text('A number above zero'), findsOneWidget);
    });

    testWidgets('a medicine given before is one tap, with its last dose', (
      tester,
    ) async {
      await openSheet(
        tester,
        history: [
          dose('Ibuprofen', hoursAgo: 2, dose: 50, unit: DoseUnit.mg),
          dose('Tylenol', hoursAgo: 8, dose: 2.5, unit: DoseUnit.ml),
        ],
      );
      await tapIn(tester, find.widgetWithText(ActionChip, 'Ibuprofen'));
      await tapIn(tester, save());

      final saved = meds.added.single;
      expect(saved.name, 'Ibuprofen');
      expect(saved.dose, 50);
      expect(saved.unit, DoseUnit.mg);
    });

    testWidgets('editing keeps who gave it', (tester) async {
      await openSheet(
        tester,
        existing: dose(
          'Tylenol',
          hoursAgo: 1,
          dose: 2.5,
          unit: DoseUnit.ml,
          by: 'Alex',
          id: 'm1',
        ),
      );
      expect(find.text('Edit medicine'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Dose (optional)'),
        '3',
      );
      await tapIn(tester, find.widgetWithText(FilledButton, 'Save changes'));
      expect(meds.updated.single.dose, 3);
      expect(meds.updated.single.byName, 'Alex');
    });

    testWidgets('records the wait chosen before the next dose', (tester) async {
      await openSheet(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Medicine'),
        'Tylenol',
      );
      await tapIn(tester, find.widgetWithText(ChoiceChip, '6 h'));
      await tapIn(tester, save());
      expect(meds.added.single.waitHours, 6);
    });

    testWidgets('a medicine given before brings its wait, and when it was', (
      tester,
    ) async {
      await openSheet(
        tester,
        history: [dose('Tylenol', hoursAgo: 8, dose: 2.5, wait: 6)],
      );
      await tapIn(tester, find.widgetWithText(ActionChip, 'Tylenol'));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '6 h'))
            .selected,
        isTrue,
      );
      expect(find.textContaining('Last given 8 hr ago'), findsOneWidget);
      expect(find.textContaining('1 in the last 24 hr'), findsOneWidget);
    });

    testWidgets('inside the wait, it asks before logging', (tester) async {
      await openSheet(
        tester,
        history: [dose('Tylenol', hoursAgo: 2, dose: 2.5, wait: 6)],
      );
      await tapIn(tester, find.widgetWithText(ActionChip, 'Tylenol'));
      await tapIn(tester, save());
      expect(find.text('Before the wait is over'), findsOneWidget);
      expect(find.textContaining('2 hr ago'), findsWidgets);

      // Cancel keeps the sheet, and saves nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(meds.added, isEmpty);

      // Asked again, and logged anyway: a doctor may have said to.
      await tapIn(tester, save());
      await tester.tap(find.text('Log anyway'));
      await tester.pumpAndSettle();
      expect(meds.added.single.name, 'Tylenol');
    });

    testWidgets('after the wait, it just logs', (tester) async {
      await openSheet(
        tester,
        history: [dose('Tylenol', hoursAgo: 7, dose: 2.5, wait: 6)],
      );
      await tapIn(tester, find.widgetWithText(ActionChip, 'Tylenol'));
      await tapIn(tester, save());
      expect(find.text('Before the wait is over'), findsNothing);
      expect(meds.added, hasLength(1));
    });

    testWidgets('says it records, and does not advise', (tester) async {
      await openSheet(tester);
      expect(find.textContaining('Follow the label or your doctor'), findsOne);
    });

    testWidgets('fits a small phone at the largest text', (tester) async {
      await openSheet(
        tester,
        size: const Size(320, 640),
        textScale: 2,
        history: [
          dose('Ibuprofen', hoursAgo: 2),
          dose('Tylenol', hoursAgo: 8),
          dose('Gripe water', hoursAgo: 9),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _RecordingMeds extends MedicationRepository {
  _RecordingMeds() : super(_NoFirestore(), 'baby1', 'alice');

  final added = <MedicationEvent>[];
  final updated = <MedicationEvent>[];

  @override
  Future<String> add(MedicationEvent event) async {
    added.add(event);
    return 'm1';
  }

  @override
  Future<void> update(MedicationEvent event) async => updated.add(event);
}

class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
