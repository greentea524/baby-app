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
import 'package:baby_app/features/fridge/fridge_slots.dart';
import 'package:baby_app/features/pumping/pumping_quick_log.dart';

/// Logging a pump session straight into the fridge as a bottle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPumps pumps;
  late _RecordingFridge fridge;
  late SharedPreferences stored;

  Future<void> openSheet(
    WidgetTester tester, {
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

  testWidgets('and stays on for the next session', (tester) async {
    // A habit, not a per-session choice.
    await openSheet(tester);
    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(stored.getBool('pump_to_fridge'), isTrue);

    await openSheet(tester, remembered: true);
    expect(isOn(tester), isTrue);
  });

  testWidgets('but adds no bottle without an amount', (tester) async {
    await openSheet(tester, remembered: true);
    expect(find.text('Once there is an amount'), findsOneWidget);

    await save(tester);

    expect(pumps.added, hasLength(1));
    expect(fridge.added, isEmpty);
  });

  testWidgets('and is gone, and adds nothing, with the fridge hidden', (
    tester,
  ) async {
    // Left on from before the fridge was switched off: the switch it was
    // set with is out of sight, so it must not go on working unseen.
    await openSheet(tester, remembered: true, fridgeShown: false);
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
      remembered: true,
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

  group('where the bottle goes', () {
    FridgeBottle inSlot(String id, FridgeSlot slot) => FridgeBottle(
      id: id,
      filledAt: DateTime.now().subtract(const Duration(hours: 5)),
      amountMl: 90,
      slot: slot,
    );

    Set<FridgeSlot> enabled(WidgetTester tester) => {
      for (final seg
          in tester
              .widget<SegmentedButton<FridgeSlot>>(
                find.byType(SegmentedButton<FridgeSlot>),
              )
              .segments)
        if (seg.enabled) seg.value,
    };

    testWidgets('Other, unless an empty letter is picked', (tester) async {
      // Reported: adding a pump to the fridge overwrote a bottle.
      await openSheet(
        tester,
        remembered: true,
        shelf: [inSlot('a', FridgeSlot.a)],
      );
      final picker = tester.widget<SegmentedButton<FridgeSlot>>(
        find.byType(SegmentedButton<FridgeSlot>),
      );
      expect(picker.selected, {FridgeSlot.other});
      expect(
        find.text('Empty: B, C. Taken letters cannot be picked.'),
        findsOne,
      );

      await tester.enterText(amountField(), '110');
      await save(tester);
      expect(fridge.slots.single, FridgeSlot.other);
    });

    testWidgets('a taken letter cannot be picked', (tester) async {
      await openSheet(
        tester,
        remembered: true,
        shelf: [inSlot('a', FridgeSlot.a), inSlot('c', FridgeSlot.c)],
      );
      expect(enabled(tester), {FridgeSlot.b, FridgeSlot.other});
    });

    testWidgets('an empty one can', (tester) async {
      await openSheet(
        tester,
        remembered: true,
        shelf: [inSlot('a', FridgeSlot.a)],
      );
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<FridgeSlot>),
          matching: find.text('B'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(amountField(), '110');
      await save(tester);
      expect(fridge.slots.single, FridgeSlot.b);
    });

    testWidgets('and with A, B and C full, it says so', (tester) async {
      await openSheet(
        tester,
        remembered: true,
        shelf: [
          inSlot('a', FridgeSlot.a),
          inSlot('b', FridgeSlot.b),
          inSlot('c', FridgeSlot.c),
        ],
      );
      expect(enabled(tester), {FridgeSlot.other});
      expect(
        find.text('A, B and C are full, so it goes under Other.'),
        findsOneWidget,
      );
    });

    testWidgets('no picker while the switch is off', (tester) async {
      await openSheet(tester);
      expect(find.byType(SegmentedButton<FridgeSlot>), findsNothing);
    });
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
  final slots = <FridgeSlot>[];

  @override
  Future<String> add(FridgeBottle event) async {
    added.add(event);
    return 'b1';
  }

  @override
  Future<void> addTo(
    FridgeBottle bottle,
    FridgeSlot slot, {
    required ShelfLayout layout,
  }) async {
    added.add(bottle);
    slots.add(slot);
  }
}

/// Never touched: the recording repositories override every call that would
/// reach it.
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
