import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/format/volume_format.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/feeding_repository.dart';
import 'package:baby_app/data/repositories/fridge_repository.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/fridge/bottle_gauge.dart';
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
    MilkKind kind = MilkKind.expressed,
  }) => FridgeBottle(
    id: id,
    filledAt: now.subtract(Duration(hours: hoursAgo)),
    amountMl: ml,
    position: position,
    notes: notes,
    kind: kind,
  );

  Future<void> pumpFridge(
    WidgetTester tester, {
    List<FridgeBottle> bottles = const [],
    List<PumpingEvent> pumps = const [],
    Size size = const Size(390, 844),
    FridgeRepository? repo,
    FeedingRepository? feeds,
    List<FeedingEvent> fed = const [],
    double textScale = 1.0,
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
          if (repo != null) fridgeRepositoryProvider.overrideWithValue(repo),
          if (feeds != null) feedingRepositoryProvider.overrideWithValue(feeds),
          recentFeedingsProvider.overrideWith((ref) => Stream.value(fed)),
          recentPumpingProvider.overrideWith((ref) => Stream.value(pumps)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: FridgeScreen(now: now),
            ),
          ),
        ),
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

  group('formula', () {
    testWidgets('stands on the same shelf, named as itself', (tester) async {
      await pumpFridge(
        tester,
        bottles: [
          bottle('milk', hoursAgo: 5, ml: 90),
          bottle('tin', hoursAgo: 1, ml: 60, kind: MilkKind.formula),
        ],
      );

      expect(find.text('Breast milk'), findsOneWidget);
      expect(find.text('Formula'), findsOneWidget);
    });

    testWidgets('and the total is broken down when both are in', (
      tester,
    ) async {
      // How much of each is a different question from how much there is,
      // because the two do not keep the same way.
      await pumpFridge(
        tester,
        bottles: [
          bottle('milk', hoursAgo: 5, ml: 90),
          bottle('tin', hoursAgo: 1, ml: 60, kind: MilkKind.formula),
        ],
      );

      expect(find.text('2 bottles · 150 ml'), findsOneWidget);
      expect(find.text('Breast milk 90 ml  ·  Formula 60 ml'), findsOneWidget);
    });

    testWidgets('but not when the fridge holds only one kind', (tester) async {
      // It would only repeat the total above it.
      await pumpFridge(tester, bottles: [bottle('milk', hoursAgo: 5, ml: 90)]);

      expect(find.text('1 bottle · 90 ml'), findsOneWidget);
      expect(find.text('Breast milk 90 ml'), findsNothing);
    });

    testWidgets('and is a choice when adding, which relabels the time', (
      tester,
    ) async {
      await pumpFridge(tester);
      await tester.tap(find.text('Add bottle'));
      await tester.pumpAndSettle();

      // Expressed to begin with: it is the kind the prefill makes sense for.
      expect(find.textContaining('Pumped'), findsOneWidget);

      await tester.tap(find.text('Formula'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Made up'), findsOneWidget);
      expect(find.textContaining('Pumped'), findsNothing);
    });

    testWidgets('and choosing it drops a prefill that was never its own', (
      tester,
    ) async {
      // A formula bottle carrying a pump session's yield would be wrong data,
      // quietly. Choosing Formula clears it; choosing Breast milk puts it
      // back.
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
      expect(find.text('135'), findsOneWidget);

      await tester.tap(find.text('Formula'));
      await tester.pumpAndSettle();
      expect(find.text('135'), findsNothing);

      await tester.tap(find.text('Breast milk'));
      await tester.pumpAndSettle();
      expect(find.text('135'), findsOneWidget);
    });

    testWidgets('and whole milk stands there too, poured', (tester) async {
      await pumpFridge(
        tester,
        bottles: [
          bottle('jug', hoursAgo: 1, ml: 150, kind: MilkKind.wholeMilk),
        ],
      );
      expect(find.text('Whole milk'), findsOneWidget);
      await tester.tap(find.text('150'));
      await tester.pumpAndSettle();
      // Its time means when it was poured.
      expect(find.textContaining('Poured'), findsOneWidget);
    });

    testWidgets('and a split formula bottle stays formula', (tester) async {
      await pumpFridge(
        tester,
        bottles: [bottle('tin', hoursAgo: 1, ml: 100, kind: MilkKind.formula)],
      );
      await tester.tap(find.text('100'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Both bottles stay formula'), findsOneWidget);
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

  group('removing one', () {
    Future<_RecordingFridge> remove(WidgetTester tester, FridgeBottle b) async {
      final repo = _RecordingFridge();
      await pumpFridge(tester, bottles: [b], repo: repo);
      await tester.tap(find.text(formatMl(b.amountMl)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('takes it off the shelf', (tester) async {
      final repo = await remove(tester, bottle('a', hoursAgo: 2, ml: 90));
      expect(repo.deleted, ['a']);
    });

    testWidgets('with no undo and no message over the shelf', (tester) async {
      // The bottle leaving the shelf is the confirmation. The old bar said so
      // with an Undo, and stayed until tapped.
      await remove(tester, bottle('a', hoursAgo: 2, ml: 90));

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Undo'), findsNothing);
    });
  });

  group('finishing one', () {
    testWidgets('every bottle has the button, on its own card', (tester) async {
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 5), bottle('b', hoursAgo: 1)],
        size: const Size(834, 1194),
      );
      expect(find.widgetWithText(FilledButton, 'Finished'), findsNWidgets(2));
    });

    Finder finishedOn(String amount) => find.descendant(
      of: find.ancestor(of: find.text(amount), matching: find.byType(Card)),
      matching: find.widgetWithText(FilledButton, 'Finished'),
    );

    testWidgets('opens the bottle log with that bottle in it', (tester) async {
      // A bottle out of the fridge is a feed. Removing it without logging one
      // meant logging it again by hand from Home.
      final repo = _RecordingFridge();
      await pumpFridge(
        tester,
        bottles: [
          bottle('old', hoursAgo: 5, ml: 120),
          bottle('new', hoursAgo: 1, ml: 60),
        ],
        repo: repo,
        feeds: _RecordingFeeds(),
        size: const Size(834, 1194),
      );

      await tester.tap(finishedOn('120'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Bottle')),
        findsOneWidget,
      );
      // That bottle's amount, and a word on where it came from.
      expect(
        find.descendant(
          of: sheet,
          matching: find.widgetWithText(TextField, '120'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'From the fridge, pumped 9:00 AM. Saving takes it off the shelf.',
        ),
        findsOneWidget,
      );
      // Nothing has happened to the bottle yet.
      expect(repo.deleted, isEmpty);
    });

    testWidgets('and saving logs the feed and takes it off the shelf', (
      tester,
    ) async {
      final repo = _RecordingFridge();
      final feeds = _RecordingFeeds();
      await pumpFridge(
        tester,
        bottles: [
          bottle('old', hoursAgo: 5, ml: 120),
          bottle('new', hoursAgo: 1, ml: 60),
        ],
        repo: repo,
        feeds: feeds,
        size: const Size(834, 1194),
      );

      await tester.tap(finishedOn('120'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(feeds.added, hasLength(1));
      final feed = feeds.added.single;
      expect(feed.type, FeedingType.bottle);
      expect(feed.amountMl, 120);
      expect(feed.notes, isNull);
      // Now, not when it was pumped: the feed is happening now.
      expect(
        DateTime.now().difference(feed.startTime).inMinutes.abs(),
        lessThan(2),
      );
      // That bottle, and only that one. And no message: the bottle leaving
      // is the answer.
      expect(repo.deleted, ['old']);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('logs what was drunk, when not all of it was', (tester) async {
      final repo = _RecordingFridge();
      final feeds = _RecordingFeeds();
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2, ml: 120)],
        repo: repo,
        feeds: feeds,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Finished'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField).first,
        ),
        '90',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(feeds.added.single.amountMl, 90);
      expect(repo.deleted, ['a']);
    });

    testWidgets('keeps the bottle if the sheet is closed without saving', (
      tester,
    ) async {
      // A mistaken press costs nothing.
      final repo = _RecordingFridge();
      final feeds = _RecordingFeeds();
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2, ml: 90)],
        repo: repo,
        feeds: feeds,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Finished'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(feeds.added, isEmpty);
      expect(repo.deleted, isEmpty);
    });

    testWidgets('logs the feed as whatever the bottle held', (tester) async {
      // Once the bottle is gone, the feed is the only record that it was
      // formula — as its milk, with the bottle's notes left as they were.
      final feeds = _RecordingFeeds();
      await pumpFridge(
        tester,
        bottles: [
          bottle(
            'tin',
            hoursAgo: 1,
            ml: 60,
            kind: MilkKind.formula,
            notes: 'for daycare',
          ),
        ],
        repo: _RecordingFridge(),
        feeds: feeds,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Finished'));
      await tester.pumpAndSettle();
      expect(find.textContaining('made up 1:00 PM'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(feeds.added.single.milk, MilkKind.formula);
      expect(feeds.added.single.notes, 'for daycare');
    });

    testWidgets('never opens the bottle itself', (tester) async {
      // A button of its own inside the card, so the press is never also a
      // tap on the card.
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2, ml: 90)],
        repo: _RecordingFridge(),
        feeds: _RecordingFeeds(),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Finished'));
      await tester.pumpAndSettle();

      expect(find.text('Edit bottle'), findsNothing);
    });

    testWidgets('and is there on a short shelf too', (tester) async {
      // A phone on its side: the bottle moves beside its numbers, and the
      // button stays at the foot of the card.
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2, ml: 90)],
        size: const Size(844, 390),
      );
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, 'Finished'), findsOneWidget);
    });
  });

  group('each bottle is drawn filled to what is in it', () {
    testWidgets('and every bottle stands at the same level', (tester) async {
      // A note is an extra line. When the card grew for it, that bottle was
      // pushed up above its neighbours — on a row whose point is comparing
      // levels at a glance. The line is kept whether or not there is a note.
      await pumpFridge(
        tester,
        bottles: [
          bottle('plain', hoursAgo: 5, ml: 120),
          bottle('noted', hoursAgo: 3, ml: 90, notes: 'for daycare'),
          bottle('tin', hoursAgo: 1, ml: 60, kind: MilkKind.formula),
        ],
        size: const Size(834, 1194),
      );

      final tops = tester
          .widgetList<CustomPaint>(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is BottlePainter,
            ),
          )
          .map((w) => tester.getRect(find.byWidget(w)).top)
          .toList();
      expect(tops, hasLength(3));
      for (final top in tops) {
        expect(top, moreOrLessEquals(tops.first, epsilon: 0.5));
      }
    });

    BottlePainter painterFor(WidgetTester tester, String amount) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.ancestor(of: find.text(amount), matching: find.byType(Card)),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is BottlePainter,
          ),
        ),
      );
      return paint.painter! as BottlePainter;
    }

    testWidgets('against the 120 ml the household\'s bottles hold', (
      tester,
    ) async {
      await pumpFridge(
        tester,
        bottles: [
          bottle('half', hoursAgo: 5, ml: 60),
          bottle('full', hoursAgo: 3, ml: 120),
          bottle('quarter', hoursAgo: 1, ml: 30),
        ],
        size: const Size(834, 1194),
      );

      expect(painterFor(tester, '60').level, 0.5);
      expect(painterFor(tester, '120').level, 1.0);
      expect(painterFor(tester, '30').level, 0.25);
    });

    testWidgets('and says how full to a screen reader', (tester) async {
      // The drawing is otherwise invisible to one. The card is a single
      // tappable thing, so its label is merged into the card's own — which is
      // what a screen reader should read out: the bottle, how full, and when.
      final semantics = tester.ensureSemantics();
      await pumpFridge(tester, bottles: [bottle('a', hoursAgo: 2, ml: 90)]);

      expect(find.bySemanticsLabel(RegExp('75% full')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('in a different colour for formula', (tester) async {
      await pumpFridge(
        tester,
        bottles: [
          bottle('milk', hoursAgo: 5, ml: 90),
          bottle('tin', hoursAgo: 1, ml: 60, kind: MilkKind.formula),
        ],
      );
      expect(
        painterFor(tester, '60').milk,
        isNot(painterFor(tester, '90').milk),
      );
    });

    testWidgets('standing above its numbers on a tall shelf', (tester) async {
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2, ml: 90)],
        size: const Size(390, 844),
      );
      final drawing = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BottlePainter,
        ),
      );
      expect(drawing.bottom, lessThan(tester.getRect(find.text('90')).top));
    });

    testWidgets('and beside them on a short one, without overflowing', (
      tester,
    ) async {
      // A phone on its side: there is not the height for a bottle above four
      // lines, so it moves beside them.
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2, ml: 90)],
        size: const Size(844, 390),
      );
      expect(tester.takeException(), isNull);

      final drawing = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BottlePainter,
        ),
      );
      expect(drawing.right, lessThan(tester.getRect(find.text('90')).left));
    });

    testWidgets('at every screen and text size, visibly', (tester) async {
      // Checked for errors alone, this let through a shelf drawn at no height:
      // a small phone at the largest text size, where the summary took nearly
      // all the room, drew its bottles invisibly and threw nothing. So each
      // card must also have real height, and the Finished button must not
      // have wrapped into a tower — it once reached 160pt.
      const sizes = [
        Size(390, 844), // phone
        Size(844, 390), // phone on its side
        Size(320, 568), // small phone
        Size(768, 1024), // tablet
        Size(1024, 768), // tablet on its side
      ];
      for (final size in sizes) {
        for (final scale in const [1.0, 1.5, 2.0]) {
          await tester.pumpWidget(const SizedBox());
          await pumpFridge(
            tester,
            bottles: [
              bottle('a', hoursAgo: 2, ml: 90, notes: 'for daycare'),
              bottle('b', hoursAgo: 1, ml: 120),
            ],
            size: size,
            textScale: scale,
          );
          final where = '$size at ${scale}x';
          expect(tester.takeException(), isNull, reason: where);
          expect(
            tester.getSize(find.byType(Card).first).height,
            greaterThan(150),
            reason: where,
          );
          expect(
            tester.getSize(find.byType(FilledButton).first).height,
            lessThan(60),
            reason: where,
          );
        }
      }
    });

    testWidgets('and the last one is not hidden under the Add button', (
      tester,
    ) async {
      await pumpFridge(
        tester,
        bottles: [bottle('a', hoursAgo: 2, ml: 90)],
        size: const Size(390, 844),
      );
      final card = tester.getRect(find.byType(Card));
      final add = tester.getRect(find.byType(FloatingActionButton));
      expect(card.bottom, lessThanOrEqualTo(add.top));
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

    testWidgets('and says the amount came from it', (tester) async {
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

      expect(find.textContaining('Amount from your'), findsOneWidget);
      // Taken out: it did not earn its place. Typing over the amount does
      // the same job.
      expect(find.text('Start blank'), findsNothing);
    });

    testWidgets("but starts the time at now, not the session's", (
      tester,
    ) async {
      // Reported: the time sat on the pump's, when the bottle is going in
      // the fridge now.
      final repo = _RecordingFridge();
      await pumpFridge(
        tester,
        repo: repo,
        pumps: [
          PumpingEvent(
            id: 'p1',
            time: DateTime.now().subtract(const Duration(hours: 3)),
            amountMl: 135,
          ),
        ],
      );
      await tester.tap(find.text('Add bottle'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to fridge'));
      await tester.pumpAndSettle();

      final added = repo.added.single;
      expect(added.amountMl, 135);
      expect(
        DateTime.now().difference(added.filledAt).inMinutes.abs(),
        lessThan(2),
      );
    });

    testWidgets('and drops the note once the amount is typed over', (
      tester,
    ) async {
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
      await tester.enterText(find.widgetWithText(TextField, '135'), '60');
      await tester.pumpAndSettle();

      expect(find.textContaining('Amount from your'), findsNothing);
    });

    testWidgets('but not on a session that is already in the fridge', (
      tester,
    ) async {
      // Reported: every new bottle opened on the same pump, long after that
      // milk had been bottled. A bottle filled after the session is that
      // session's milk.
      final pumped = now.subtract(const Duration(minutes: 40));
      await pumpFridge(
        tester,
        bottles: [
          FridgeBottle(
            id: 'b1',
            filledAt: pumped.add(const Duration(minutes: 10)),
            amountMl: 135,
          ),
        ],
        pumps: [PumpingEvent(id: 'p1', time: pumped, amountMl: 135)],
      );
      await tester.tap(find.text('Add bottle'));
      await tester.pumpAndSettle();

      expect(find.text('Add a bottle'), findsOneWidget);
      expect(find.textContaining('Amount from your'), findsNothing);
      // The shelf's own card shows 135; the sheet's field must not.
      expect(
        find.descendant(of: find.byType(TextField), matching: find.text('135')),
        findsNothing,
      );
    });

    testWidgets('nor on one that has been fed since', (tester) async {
      // Bottled, then finished: the bottle is off the shelf, and the feed
      // it was logged as is what says the session is dealt with.
      final pumped = now.subtract(const Duration(hours: 3));
      await pumpFridge(
        tester,
        pumps: [PumpingEvent(id: 'p1', time: pumped, amountMl: 135)],
        fed: [
          FeedingEvent(
            id: 'f1',
            type: FeedingType.bottle,
            startTime: now.subtract(const Duration(hours: 1)),
            amountMl: 135,
          ),
        ],
      );
      await tester.tap(find.text('Add bottle'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Amount from your'), findsNothing);
      expect(find.text('135'), findsNothing);
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

/// A fridge that writes nothing and remembers what it was asked to write.
///
/// There is no Firestore fake in this project, and removing and undoing both
/// need a repository to reach at all. This one stands in for the real thing
/// at exactly the two calls those take.
class _RecordingFridge extends FridgeRepository {
  _RecordingFridge() : super(_NoFirestore(), 'baby1', 'alice');

  final added = <FridgeBottle>[];
  final deleted = <String>[];

  @override
  Future<String> add(FridgeBottle event) async {
    added.add(event);
    return 'restored';
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

class _RecordingFeeds extends FeedingRepository {
  _RecordingFeeds() : super(_NoFirestore(), 'baby1', 'alice');

  final added = <FeedingEvent>[];

  @override
  Future<String> add(FeedingEvent event) async {
    added.add(event);
    return 'feed1';
  }
}

/// Never touched: the recording repositories override every call that would
/// reach it.
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
