import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/fridge/fridge_screen.dart';

/// The fridge shelf: what is in it, in what order, and what you can do to it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 25, 14);

  FridgeBottle bottle(
    String id, {
    required int hoursAgo,
    double ml = 100,
    int? position,
    String? notes,
  }) => FridgeBottle(
    id: id,
    pumpedAt: now.subtract(Duration(hours: hoursAgo)),
    amountMl: ml,
    position: position,
    notes: notes,
  );

  Future<void> pumpFridge(
    WidgetTester tester, {
    List<FridgeBottle> bottles = const [],
    List<PumpingEvent> pumps = const [],
    Size size = const Size(390, 844),
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric'});
    final stored = await SharedPreferences.getInstance();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          // Signed out, so the repository is null and nothing tries to write.
          // This is about what the shelf shows, not what it saves.
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          fridgeBottlesProvider.overrideWith((ref) => Stream.value(bottles)),
          recentPumpingProvider.overrideWith((ref) => Stream.value(pumps)),
        ],
        child: MaterialApp(home: FridgeScreen(now: now)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the shelf', () {
    testWidgets('puts the oldest bottle on the left', (tester) async {
      // Left to right, oldest first: the reading order and the order milk
      // should be used in are the same order.
      await pumpFridge(
        tester,
        bottles: [
          bottle('new', hoursAgo: 1, ml: 60),
          bottle('old', hoursAgo: 9, ml: 120),
        ],
      );

      final old = tester.getRect(find.text('120'));
      final fresh = tester.getRect(find.text('60'));
      expect(old.left, lessThan(fresh.left));
      expect(old.top, moreOrLessEquals(fresh.top, epsilon: 0.5));
    });

    testWidgets('says how many and how much', (tester) async {
      await pumpFridge(
        tester,
        bottles: [
          bottle('a', hoursAgo: 2, ml: 90),
          bottle('b', hoursAgo: 5, ml: 65),
        ],
      );

      expect(find.text('2 bottles · 155 ml'), findsOneWidget);
    });

    testWidgets('and counts one bottle as one', (tester) async {
      await pumpFridge(tester, bottles: [bottle('a', hoursAgo: 2, ml: 90)]);
      expect(find.text('1 bottle · 90 ml'), findsOneWidget);
    });

    testWidgets('shows when each was pumped, and how old that is', (
      tester,
    ) async {
      // The two facts the shelf exists for: which bottle this is, and whether
      // the milk in it is still good.
      await pumpFridge(tester, bottles: [bottle('a', hoursAgo: 3, ml: 90)]);

      expect(find.text('3 hr ago'), findsOneWidget);
      expect(find.textContaining('11:00'), findsOneWidget);
    });

    testWidgets('and a note when one was left', (tester) async {
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 3, notes: 'for daycare')],
      );
      expect(find.text('for daycare'), findsOneWidget);
    });
  });

  group('when it is empty', () {
    testWidgets('it says so rather than showing an empty band', (tester) async {
      await pumpFridge(tester);

      expect(find.text('Nothing in the fridge'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
      // Adding is still the point of the screen, so the way in stays.
      expect(find.text('Add bottle'), findsOneWidget);
    });
  });

  group('the order', () {
    testWidgets('follows positions once they are set', (tester) async {
      await pumpFridge(
        tester,
        bottles: [
          bottle('old', hoursAgo: 9, ml: 120, position: 1),
          bottle('new', hoursAgo: 1, ml: 60, position: 0),
        ],
      );

      expect(
        tester.getRect(find.text('60')).left,
        lessThan(tester.getRect(find.text('120')).left),
        reason: 'the hand-arranged order wins over age',
      );
    });

    testWidgets('and offers a way back to age order, but only then', (
      tester,
    ) async {
      // A button that resets an order nobody has changed would be a button
      // that does nothing.
      await pumpFridge(tester, bottles: [bottle('a', hoursAgo: 2)]);
      expect(find.text('Sort by age'), findsNothing);
      expect(find.text('Oldest on the left — the end to take from.'), findsOne);

      // Torn down between the two: pumping a second widget tree reuses the
      // ProviderScope, which updates in place rather than re-resolving the
      // overridden stream.
      await tester.pumpWidget(const SizedBox());
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2, position: 0)],
      );
      expect(find.text('Sort by age'), findsOneWidget);
      expect(find.text('Arranged by hand, to match your fridge.'), findsOne);
    });

    testWidgets('and every bottle carries a drag handle', (tester) async {
      // Dragging is deliberate and tapping opens the bottle. The default
      // long-press handles would make those two the same gesture.
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2), bottle('b', hoursAgo: 5)],
      );
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));
    });
  });

  group('a bottle', () {
    testWidgets('opens to be edited, split or removed', (tester) async {
      await pumpFridge(tester, bottles: [bottle('a', hoursAgo: 2, ml: 90)]);
      await tester.tap(find.text('90'));
      await tester.pumpAndSettle();

      expect(find.text('Edit bottle'), findsOneWidget);
      expect(find.text('Split'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('and the split sheet shows both halves adding up', (
      tester,
    ) async {
      await pumpFridge(tester, bottles: [bottle('a', hoursAgo: 2, ml: 100)]);
      await tester.tap(find.text('100'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      expect(find.text('Split this bottle'), findsOneWidget);
      // Half each by default, and the sum said out loud.
      expect(find.text('50 ml'), findsNWidgets(2));
      expect(find.text('Adds up to 100 ml.'), findsOneWidget);
    });

    testWidgets('but one too small to divide says so', (tester) async {
      // Five millilitres a side is the floor; a 9 ml bottle cannot make two.
      await pumpFridge(tester, bottles: [bottle('a', hoursAgo: 2, ml: 9)]);
      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      expect(find.text('There is not enough here to divide.'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });
  });

  group('adding one', () {
    testWidgets('opens on the last pump session', (tester) async {
      // Where the milk came from nine times in ten, so the sheet is usually
      // one tap rather than a form.
      await pumpFridge(
        tester,
        pumps: [
          PumpingEvent(
            id: 'p1',
            time: now.subtract(const Duration(minutes: 20)),
            amountMl: 135,
          ),
        ],
      );
      await tester.tap(find.text('Add bottle'));
      await tester.pumpAndSettle();

      expect(find.text('Add a bottle'), findsOneWidget);
      expect(find.text('135'), findsOneWidget);
    });

    testWidgets('and on an empty amount when nothing has been pumped', (
      tester,
    ) async {
      await pumpFridge(tester);
      await tester.tap(find.text('Add bottle'));
      await tester.pumpAndSettle();

      expect(find.text('Add a bottle'), findsOneWidget);
      // Nothing to prefill from, so nothing is invented.
      expect(find.text('135'), findsNothing);
    });
  });
}
