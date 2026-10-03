import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/fridge_repository.dart';
import 'package:baby_app/data/repositories/pumping_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/pumping/pumping_quick_log.dart';

/// Logging a pump session straight into the fridge as a bottle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPumps pumps;
  late _RecordingFridge fridge;
  late SharedPreferences stored;

  Future<void> openSheet(
    WidgetTester tester, {
    bool switchOn = false,
    bool? remembered,
    bool? fridgeShown,
    PumpingEvent? existing,
    List<FridgeBottle> shelf = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      'unit_system': 'metric',
      'pump_to_fridge': ?remembered,
      'show_fridge': ?fridgeShown,
    });
    stored = await SharedPreferences.getInstance();
    pumps = _RecordingPumps();
    fridge = _RecordingFridge();
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          pumpingRepositoryProvider.overrideWithValue(pumps),
          fridgeRepositoryProvider.overrideWithValue(fridge),
          fridgeBottlesProvider.overrideWith((ref) => Stream.value(shelf)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showPumpingQuickLog(context, existing: existing),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (switchOn) {
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Add to the fridge'),
      );
      await tester.pumpAndSettle();
    }
  }

  Finder amountField() => find.byType(TextField).first;
  Finder toggle() => find.widgetWithText(SwitchListTile, 'Add to the fridge');
  bool isOn(WidgetTester tester) =>
      tester.widget<SwitchListTile>(toggle()).value;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('is off to begin with, and adds nothing', (tester) async {
    // A bottle nobody put in the fridge is a wrong answer on the shelf.
    await openSheet(tester);
    expect(isOn(tester), isFalse);

    await tester.enterText(amountField(), '110');
    await save(tester);

    expect(pumps.added, hasLength(1));
    expect(fridge.added, isEmpty);
  });

  testWidgets('switched on, the session goes in the fridge as a bottle', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.enterText(amountField(), '110');
    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(find.text('As a 110 ml bottle'), findsOneWidget);

    await save(tester);

    final session = pumps.added.single;
    final bottle = fridge.added.single;
    expect(bottle.amountMl, 110);
    expect(bottle.kind, MilkKind.expressed);
    // As old as the pumping, and matched to its session by that time.
    expect(bottle.filledAt, session.time);
  });

  testWidgets('and is off again the next time', (tester) async {
    // A choice for this session, not remembered: most pumped milk is fed
    // fresh, so each session starts from not bottling it.
    await openSheet(tester, switchOn: true);
    expect(isOn(tester), isTrue);

    // Gone, sheet and all, before it is opened afresh.
    await tester.pumpWidget(const SizedBox());
    await openSheet(tester);
    expect(isOn(tester), isFalse);
  });

  testWidgets('even where it was left on before it was per session', (
    tester,
  ) async {
    // Devices that remembered it switched on start off too.
    await openSheet(tester, remembered: true);
    expect(isOn(tester), isFalse);

    await tester.enterText(amountField(), '110');
    await save(tester);
    expect(fridge.added, isEmpty);
  });

  testWidgets('but adds no bottle without an amount', (tester) async {
    await openSheet(tester, switchOn: true);
    expect(find.text('Once there is an amount'), findsOneWidget);

    await save(tester);

    expect(pumps.added, hasLength(1));
    expect(fridge.added, isEmpty);
  });

  testWidgets('and is gone, and adds nothing, with the fridge hidden', (
    tester,
  ) async {
    await openSheet(tester, fridgeShown: false);
    expect(toggle(), findsNothing);

    await tester.enterText(amountField(), '110');
    await save(tester);

    expect(pumps.added, hasLength(1));
    expect(fridge.added, isEmpty);
  });

  testWidgets('and is not offered when editing a session', (tester) async {
    // Editing a session is not pumping it again.
    await openSheet(
      tester,
      existing: PumpingEvent(
        id: 'p1',
        time: DateTime.now().subtract(const Duration(hours: 1)),
        amountMl: 90,
      ),
    );
    expect(toggle(), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(pumps.updated, hasLength(1));
    expect(fridge.added, isEmpty);
  });

  testWidgets('and asks for no slot: the bottle stands by its age', (
    tester,
  ) async {
    await openSheet(tester, switchOn: true);
    expect(find.textContaining('Slot'), findsNothing);
    expect(find.textContaining('Other'), findsNothing);

    await tester.enterText(amountField(), '110');
    await save(tester);
    expect(fridge.added.single.amountMl, 110);
  });
}

class _RecordingPumps extends PumpingRepository {
  _RecordingPumps() : super(_NoFirestore(), 'baby1', 'alice');

  final added = <PumpingEvent>[];
  final updated = <PumpingEvent>[];

  @override
  Future<String> add(PumpingEvent event) async {
    added.add(event);
    return 'p1';
  }

  @override
  Future<void> update(PumpingEvent event) async => updated.add(event);
}

class _RecordingFridge extends FridgeRepository {
  _RecordingFridge() : super(_NoFirestore(), 'baby1', 'alice');

  final added = <FridgeBottle>[];

  @override
  Future<String> add(FridgeBottle event) async {
    added.add(event);
    return 'b1';
  }
}

/// Never touched: the recording repositories override every call that would
/// reach it.
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
