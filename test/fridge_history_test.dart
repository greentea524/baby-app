import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/data/models/fridge_log_entry.dart';
import 'package:baby_app/data/repositories/fridge_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/fridge/fridge_history_screen.dart';

/// The fridge's history: what was added, fed, removed, split and combined,
/// and putting a removed bottle back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 4, 15);

  FridgeLogEntry entry(
    String id,
    FridgeAction action,
    DateTime at, {
    String bottle = 'b1',
    double ml = 120,
    double? other,
    MilkKind kind = MilkKind.expressed,
  }) => FridgeLogEntry(
    id: id,
    action: action,
    at: at,
    bottleId: bottle,
    amountMl: ml,
    kind: kind,
    filledAt: DateTime(2026, 11, 3, 9, 30),
    otherMl: other,
  );

  Future<_RecordingFridge> pump(
    WidgetTester tester, {
    required List<FridgeLogEntry> log,
    List<FridgeBottle> shelf = const [],
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    final repo = _RecordingFridge();
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          fridgeRepositoryProvider.overrideWithValue(repo),
          fridgeLogProvider.overrideWith((ref) => Stream.value(log)),
          fridgeShelfProvider.overrideWithValue(shelf),
        ],
        child: MaterialApp(home: FridgeHistoryScreen(now: now)),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('says what happened, a day at a time', (tester) async {
    await pump(
      tester,
      log: [
        entry(
          '5',
          FridgeAction.combined,
          DateTime(2026, 11, 4, 14),
          ml: 90,
          other: 30,
        ),
        entry(
          '6',
          FridgeAction.combined,
          DateTime(2026, 11, 4, 13),
          bottle: 'b9',
          ml: 60,
          other: 60,
        ),
        entry(
          '4',
          FridgeAction.split,
          DateTime(2026, 11, 4, 12),
          ml: 150,
          other: 70,
        ),
        entry('3', FridgeAction.fed, DateTime(2026, 11, 4, 10)),
        entry(
          '2',
          FridgeAction.added,
          DateTime(2026, 11, 3, 9, 30),
          bottle: 'b2',
        ),
        entry(
          '1',
          FridgeAction.added,
          DateTime(2026, 10, 30, 8),
          bottle: 'b3',
          kind: MilkKind.formula,
        ),
      ],
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Poured 30 ml of 90 ml breast milk'), findsOneWidget);
    expect(find.text('Poured all 60 ml breast milk'), findsOneWidget);
    expect(find.text('Split 150 ml breast milk'), findsOneWidget);
    expect(find.textContaining('Into 80 ml and 70 ml'), findsOneWidget);
    expect(find.text('Fed 120 ml breast milk'), findsOneWidget);
    expect(find.text('Added 120 ml formula'), findsOneWidget);
  });

  testWidgets('puts a removed bottle back, as it was', (tester) async {
    final removed = entry('2', FridgeAction.removed, DateTime(2026, 11, 4, 13));
    final repo = await pump(
      tester,
      log: [removed, entry('1', FridgeAction.added, DateTime(2026, 11, 4, 9))],
    );
    expect(find.text('Removed 120 ml breast milk'), findsOneWidget);
    await tester.tap(find.text('Put back'));
    await tester.pump();
    expect(repo.restored.single.id, '2');
    expect(repo.restored.single.bottle.id, 'b1');
    expect(repo.restored.single.bottle.amountMl, 120);
    expect(find.text('Back in the fridge'), findsOneWidget);
  });

  testWidgets('but not one that is on the shelf again', (tester) async {
    await pump(
      tester,
      log: [entry('2', FridgeAction.removed, DateTime(2026, 11, 4, 13))],
      shelf: [
        FridgeBottle(
          id: 'b1',
          filledAt: DateTime(2026, 11, 3, 9, 30),
          amountMl: 120,
        ),
      ],
    );
    expect(find.text('Put back'), findsNothing);
  });

  testWidgets('nor an older removal of a bottle put back since', (
    tester,
  ) async {
    await pump(
      tester,
      log: [
        entry('3', FridgeAction.fed, DateTime(2026, 11, 4, 14)),
        entry('2', FridgeAction.restored, DateTime(2026, 11, 4, 13)),
        entry('1', FridgeAction.removed, DateTime(2026, 11, 4, 12)),
      ],
    );
    expect(find.text('Removed 120 ml breast milk'), findsOneWidget);
    expect(find.text('Put back'), findsNothing);
  });

  testWidgets('says so when there is nothing yet', (tester) async {
    await pump(tester, log: const []);
    expect(find.textContaining('Nothing yet.'), findsOneWidget);
  });

  test('an entry keeps the bottle whole, to put it back', () {
    final bottle = FridgeBottle(
      id: 'b9',
      filledAt: DateTime(2026, 11, 3, 9),
      amountMl: 95,
      kind: MilkKind.formula,
      notes: 'Split',
    );
    final e = FridgeLogEntry.of(FridgeAction.removed, bottle, at: now);
    final back = e.bottle;
    expect(back.id, 'b9');
    expect(back.amountMl, 95);
    expect(back.kind, MilkKind.formula);
    expect(back.filledAt, bottle.filledAt);
    expect(back.notes, 'Split');
    expect(e.toMap()['action'], 'removed');
  });
}

class _RecordingFridge extends FridgeRepository {
  _RecordingFridge() : super(_NoFirestore(), 'baby1', 'alice');

  final restored = <FridgeLogEntry>[];

  @override
  Future<void> restore(FridgeLogEntry removed) async => restored.add(removed);
}

class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
