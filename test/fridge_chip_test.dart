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

/// Tapping a fridge chip in the bottle form pours from that bottle: saving
/// the feed takes it off the shelf.
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
  Finder amountField() => find.widgetWithText(TextField, 'Amount');
  Finder notesField() => find.widgetWithText(TextField, 'Notes (optional)');
  String notes(WidgetTester tester) =>
      tester.widget<TextField>(notesField()).controller!.text;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving takes that bottle out of the fridge', (tester) async {
    await openBottleForm(
      tester,
      shelf: [bottle('b90', 90), bottle('b120', 120, hour: 1)],
    );
    await tester.tap(chip('120 ml'));
    await tester.pumpAndSettle();

    // Said before it happens.
    expect(
      find.text('Takes the 120 ml breast milk bottle out of the fridge'),
      findsOneWidget,
    );

    await save(tester);

    expect(feeds.added.single.amountMl, 120);
    expect(fridge.deleted, ['b120']);
  });

  testWidgets('the next of two bottles holding the same amount', (
    tester,
  ) async {
    // One chip for both; the one it takes is the one on the left, which is
    // the next to be used.
    await openBottleForm(
      tester,
      shelf: [bottle('first', 90), bottle('second', 90, hour: 1)],
    );
    await tester.tap(chip('90 ml'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(fridge.deleted, ['first']);
  });

  testWidgets('even when the amount is corrected after', (tester) async {
    // Not all of it was drunk: the bottle is still out of the fridge.
    await openBottleForm(tester, shelf: [bottle('b120', 120)]);
    await tester.tap(chip('120 ml'));
    await tester.pumpAndSettle();
    await tester.enterText(amountField(), '90');
    await tester.pumpAndSettle();
    await save(tester);

    expect(feeds.added.single.amountMl, 90);
    expect(fridge.deleted, ['b120']);
  });

  testWidgets('but not once another chip is tapped instead', (tester) async {
    await openBottleForm(
      tester,
      shelf: [bottle('b120', 120)],
      pumps: [
        PumpingEvent(
          id: 'p',
          time: DateTime.now().subtract(const Duration(minutes: 30)),
          amountMl: 95,
        ),
      ],
    );
    await tester.tap(chip('120 ml'));
    await tester.pumpAndSettle();
    await tester.tap(chip('95 ml'));
    await tester.pumpAndSettle();

    expect(find.textContaining('out of the fridge'), findsNothing);
    await save(tester);

    expect(feeds.added.single.amountMl, 95);
    expect(fridge.deleted, isEmpty);
  });

  testWidgets('nor once it is told to leave the bottle', (tester) async {
    await openBottleForm(tester, shelf: [bottle('b120', 120)]);
    await tester.tap(chip('120 ml'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Leave it in the fridge'));
    await tester.pumpAndSettle();
    await save(tester);

    // The amount stays; only the bottle is left alone.
    expect(feeds.added.single.amountMl, 120);
    expect(fridge.deleted, isEmpty);
  });

  testWidgets('and closing the form leaves it on the shelf', (tester) async {
    await openBottleForm(tester, shelf: [bottle('b120', 120)]);
    await tester.tap(chip('120 ml'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(feeds.added, isEmpty);
    expect(fridge.deleted, isEmpty);
  });

  testWidgets('and the feed is of whatever the bottle held', (tester) async {
    // As finishing it from the shelf does. The notes are left alone: the
    // feed says what it was of in its own field now.
    await openBottleForm(
      tester,
      shelf: [bottle('tin', 150, kind: MilkKind.formula)],
    );
    await tester.tap(chip('150 ml'));
    await tester.pumpAndSettle();
    expect(notes(tester), isEmpty);
    await save(tester);

    expect(feeds.added.single.milk, MilkKind.formula);
  });

  testWidgets('editing a feed already logged takes nothing out', (
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

    expect(find.textContaining('out of the fridge'), findsNothing);
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
