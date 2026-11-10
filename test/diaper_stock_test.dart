import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/diaper_stock_entry.dart';
import 'package:baby_app/data/repositories/diaper_stock_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/diaper/diaper_stock.dart';
import 'package:baby_app/features/diaper/diaper_stock_screen.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// The diaper stock: worked out from packs, counts and the changes logged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 10, 15);
  DateTime hoursAgo(int h) => now.subtract(Duration(hours: h));

  DiaperStockEntry added(String id, int count, int hAgo, {String? notes}) =>
      DiaperStockEntry(
        id: id,
        action: StockAction.added,
        at: hoursAgo(hAgo),
        count: count,
        notes: notes,
      );
  DiaperStockEntry counted(String id, int count, int hAgo) => DiaperStockEntry(
    id: id,
    action: StockAction.counted,
    at: hoursAgo(hAgo),
    count: count,
  );
  List<DiaperEvent> changes(List<int> hoursBack) => [
    for (final (i, h) in hoursBack.indexed)
      DiaperEvent(id: 'd$i', type: DiaperType.wet, time: hoursAgo(h)),
  ];

  group('how many are left', () {
    test('nothing recorded is no stock at all', () {
      expect(DiaperStock.of(const [], changes([1]), lowAt: 20), isNull);
    });

    test('the last count, plus packs since, less changes since', () {
      final stock = DiaperStock.of(
        [counted('c1', 52, 48), added('a1', 44, 10), counted('c0', 9, 90)],
        // Two before the count are in it already; three since come off.
        changes([1, 5, 20, 50, 60]),
        lowAt: 20,
      )!;
      expect(stock.left, 52 + 44 - 3);
      expect(stock.used, 3);
      expect(stock.since, hoursAgo(48));
      expect(stock.level, StockLevel.ok);
    });

    test('a pack from before the count is in the count', () {
      final stock = DiaperStock.of(
        [added('a0', 50, 72), counted('c1', 30, 24)],
        changes([2]),
        lowAt: 20,
      )!;
      expect(stock.left, 29);
    });

    test('never counted, it starts from the first pack', () {
      final stock = DiaperStock.of(
        [added('a1', 40, 30), added('a2', 40, 5)],
        changes([1, 2, 31]),
        lowAt: 20,
      )!;
      expect(stock.since, hoursAgo(30));
      expect(stock.left, 80 - 2);
    });

    test('running low at the set number, and out at none', () {
      DiaperStock with_(int n) =>
          DiaperStock.of([counted('c', n, 1)], const [], lowAt: 20)!;
      expect(with_(21).level, StockLevel.ok);
      expect(with_(20).level, StockLevel.low);
      expect(with_(0).level, StockLevel.out);
      expect(
        DiaperStock.of([counted('c', 1, 5)], changes([1, 2]), lowAt: 20)!.level,
        StockLevel.out,
      );
    });

    test('and how many days that is at the recent pace', () {
      expect(diapersPerDay(changes([1, 10, 20, 30, 40, 50, 80]), now), 2);
      expect(diapersPerDay(const [], now), isNull);
      final stock = DiaperStock(
        left: 25,
        since: now,
        used: 0,
        lowAt: 20,
        perDay: 8,
      );
      expect(stock.daysLeft, 3);
    });
  });

  group('the screen', () {
    Future<_RecordingStock> pumpScreen(
      WidgetTester tester, {
      List<DiaperStockEntry> entries = const [],
      List<DiaperEvent> since = const [],
    }) async {
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      final repo = _RecordingStock();
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            diaperStockRepositoryProvider.overrideWithValue(repo),
            diaperStockEntriesProvider.overrideWith(
              (ref) => Stream.value(entries),
            ),
            diapersSinceProvider.overrideWith(
              (ref, start) => Stream.value(since),
            ),
            recentDiapersProvider.overrideWith((ref) => Stream.value(since)),
          ],
          child: MaterialApp(home: DiaperStockScreen(now: now)),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('says how to start, before anything is counted', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('No diapers counted yet'), findsOneWidget);
      expect(find.text('Add a pack'), findsOneWidget);
      expect(find.text('Count them'), findsOneWidget);
    });

    testWidgets('says how many are left, and how long they last', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        entries: [counted('c1', 60, 30)],
        since: changes([2, 5, 8, 11, 14, 17, 20, 23, 26]),
      );
      expect(find.byKey(const ValueKey('stock-left')), findsOneWidget);
      expect(find.text('51'), findsOneWidget);
      expect(find.text('diapers left'), findsOneWidget);
      expect(find.text('Counted 60'), findsOneWidget);
    });

    testWidgets('and says so when running low', (tester) async {
      await pumpScreen(tester, entries: [counted('c1', 12, 1)]);
      expect(
        find.textContaining(RegExp(r'^Running low( ·|$)')),
        findsOneWidget,
      );
    });

    testWidgets('adds a pack, one tap for a common size', (tester) async {
      final repo = await pumpScreen(tester, entries: [counted('c1', 10, 1)]);
      await tester.tap(find.text('Add a pack'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '40'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes (optional)'),
        'Size 2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      final line = repo.added.single;
      expect(line.action, StockAction.added);
      expect(line.count, 40);
      expect(line.notes, 'Size 2');
    });

    testWidgets('records a count', (tester) async {
      final repo = await pumpScreen(tester);
      await tester.tap(find.text('Count them'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '73');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save count'));
      await tester.pumpAndSettle();
      expect(repo.added.single.action, StockAction.counted);
      expect(repo.added.single.count, 73);
    });

    testWidgets('takes a line back, with an undo', (tester) async {
      final repo = await pumpScreen(
        tester,
        entries: [counted('c1', 10, 1), added('a1', 44, 0)],
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('stock-a1')),
          matching: find.byTooltip('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.deleted, ['a1']);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(repo.added.single.count, 44);
    });

    testWidgets('and sets how low is running low', (tester) async {
      await pumpScreen(tester, entries: [counted('c1', 30, 1)]);
      expect(find.text('20'), findsOneWidget);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('low-at')), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getInt('diaper_stock_low_at'),
        25,
      );
    });
  });

  group('on Home', () {
    Future<void> pumpCard(
      WidgetTester tester,
      List<DiaperStockEntry> entries,
    ) async {
      SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
      final stored = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            recentFeedingsProvider.overrideWith((ref) => Stream.value([])),
            recentDiapersProvider.overrideWith(
              (ref) => Stream.value(changes([1])),
            ),
            recentPumpingProvider.overrideWith((ref) => Stream.value([])),
            diaperStockEntriesProvider.overrideWith(
              (ref) => Stream.value(entries),
            ),
            diapersSinceProvider.overrideWith(
              (ref, start) => Stream.value(changes([1])),
            ),
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

    testWidgets('the diaper row has the stock, as a way in', (tester) async {
      await pumpCard(tester, [counted('c1', 43, 5)]);
      expect(find.byKey(const ValueKey('diaper-stock')), findsOneWidget);
      expect(find.text('42 left'), findsOneWidget);
    });

    testWidgets('and just "Stock" before anything is counted', (tester) async {
      await pumpCard(tester, const []);
      expect(find.text('Stock'), findsOneWidget);
    });

    testWidgets('and "None left" once out', (tester) async {
      await pumpCard(tester, [counted('c1', 1, 5)]);
      expect(find.text('None left'), findsOneWidget);
    });
  });
}

class _RecordingStock extends DiaperStockRepository {
  _RecordingStock() : super(_NoFirestore(), 'baby1', 'alice');

  final added = <DiaperStockEntry>[];
  final deleted = <String>[];

  @override
  Future<String> add(DiaperStockEntry event) async {
    added.add(event);
    return 'new';
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
