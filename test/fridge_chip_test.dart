import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/feeding_repository.dart';
import 'package:baby_app/data/repositories/fridge_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/feeding/feeding_quick_log.dart';

/// Tapping a fridge chip in the bottle form fills in its amount, and only
/// that: no bottle leaves the fridge except from its own card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = DateTime.now().subtract(const Duration(hours: 6));
  FridgeBottle bottle(
    String id,
    double ml, {
    int hour = 0,
    MilkKind kind = MilkKind.expressed,
  }) => FridgeBottle(
    id: id,
    filledAt: base.add(Duration(hours: hour)),
    amountMl: ml,
    kind: kind,
  );

  late _RecordingFeeds feeds;
  late _RecordingFridge fridge;

  Future<void> openBottleForm(
    WidgetTester tester, {
    required List<FridgeBottle> shelf,
    List<PumpingEvent> pumps = const [],
    FeedingEvent? existing,
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();
    feeds = _RecordingFeeds();
    fridge = _RecordingFridge();
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          feedingRepositoryProvider.overrideWithValue(feeds),
          fridgeRepositoryProvider.overrideWithValue(fridge),
          recentFeedingsProvider.overrideWith((ref) => Stream.value([])),
          recentPumpingProvider.overrideWith((ref) => Stream.value(pumps)),
          fridgeBottlesProvider.overrideWith((ref) => Stream.value(shelf)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showFeedingQuickLog(
                    context,
                    type: FeedingType.bottle,
                    existing: existing,
                  ),
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

  Finder chip(String label) => find.widgetWithText(ActionChip, label);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('a fridge chip fills the amount and takes nothing out', (
    tester,
  ) async {
    // Reported: feeding 100 ml of fresh milk, the 100 ml chip carried the
    // fridge icon, and saving took a 100 ml bottle off the shelf that was
    // still in the fridge. A chip is an amount; a bottle leaves the fridge
    // from its own card.
    await openBottleForm(
      tester,
      shelf: [bottle('b90', 90), bottle('b100', 100, hour: 1)],
    );
    await tester.tap(chip('100 ml'));
    await tester.pumpAndSettle();
    expect(find.textContaining('out of the fridge'), findsNothing);
    await save(tester);

    expect(feeds.added.single.amountMl, 100);
    expect(fridge.deleted, isEmpty);
  });

  testWidgets('nor changes what milk the feed is of', (tester) async {
    // A formula bottle of the same amount says nothing about this feed.
    await openBottleForm(
      tester,
      shelf: [bottle('tin', 150, kind: MilkKind.formula)],
    );
    await tester.tap(chip('150 ml'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(feeds.added.single.milk, MilkKind.expressed);
    expect(fridge.deleted, isEmpty);
  });

  testWidgets('and editing a feed with one takes nothing out either', (
    tester,
  ) async {
    await openBottleForm(
      tester,
      shelf: [bottle('b120', 120)],
      existing: FeedingEvent(
        id: 'f1',
        type: FeedingType.bottle,
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        amountMl: 60,
      ),
    );
    await tester.tap(chip('120 ml'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(feeds.updated.single.amountMl, 120);
    expect(fridge.deleted, isEmpty);
  });
}

class _RecordingFeeds extends FeedingRepository {
  _RecordingFeeds() : super(_NoFirestore(), 'baby1', 'alice');

  final added = <FeedingEvent>[];
  final updated = <FeedingEvent>[];

  @override
  Future<String> add(FeedingEvent event) async {
    added.add(event);
    return 'f1';
  }

  @override
  Future<void> update(FeedingEvent event) async => updated.add(event);
}

class _RecordingFridge extends FridgeRepository {
  _RecordingFridge() : super(_NoFirestore(), 'baby1', 'alice');

  final deleted = <String>[];

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

/// Never touched: the recording repositories override every call that would
/// reach it.
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
