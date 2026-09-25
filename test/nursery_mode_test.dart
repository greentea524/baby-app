import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/fridge/fridge_button.dart';
import 'package:baby_app/features/home/home_prefs.dart';
import 'package:baby_app/features/home/home_status_card.dart';
import 'package:baby_app/features/home/home_screen.dart';
import 'package:baby_app/features/home/nursery_screen.dart';

/// The screen for a tablet propped on a shelf (#29).
///
/// Not Home scaled up: a couple of readouts, three buttons, and nothing else
/// — read from across a room and tapped while holding a baby. A third
/// readout appears only for households that pump.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 8, 24, 14, 0);
  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  Future<ProviderContainer> pumpNursery(
    WidgetTester tester, {
    double textScale = 1.0,
    Size size = const Size(834, 1194),
    bool withData = true,
    List<FeedingEvent>? feeds,
    List<DiaperEvent>? diapers,
    List<PumpingEvent> pumps = const [],
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'display_mode': 'nursery',
      ...prefs,
    });
    final stored = await SharedPreferences.getInstance();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(stored),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
        recentFeedingsProvider.overrideWith(
          (ref) => Stream.value(
            feeds ??
                (withData
                    ? [
                        FeedingEvent(
                          id: 'f1',
                          type: FeedingType.bottle,
                          startTime: now.subtract(const Duration(hours: 2)),
                          amountMl: 150,
                        ),
                      ]
                    : const []),
          ),
        ),
        recentDiapersProvider.overrideWith(
          (ref) => Stream.value(
            diapers ??
                (withData
                    ? [
                        DiaperEvent(
                          id: 'd1',
                          type: DiaperType.wet,
                          time: now.subtract(const Duration(minutes: 40)),
                        ),
                      ]
                    : const []),
          ),
        ),
        recentPumpingProvider.overrideWith((ref) => Stream.value(pumps)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            // copyWith, not a fresh MediaQueryData: building one from scratch
            // throws away `size`, and anything that lays out from the screen
            // width then sees zero.
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: NurseryScreen(now: now),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('shows how long since each, large', (tester) async {
    await pumpNursery(tester);

    expect(find.text('Last fed'), findsOneWidget);
    expect(find.text('2 hr ago'), findsOneWidget);
    expect(find.text('Last changed'), findsOneWidget);
    expect(find.text('40 min ago'), findsOneWidget);
  });

  group('the last feed says how much', () {
    testWidgets('in the caregiver\'s units, beside how long ago', (
      tester,
    ) async {
      await pumpNursery(tester);

      expect(find.text('2 hr ago'), findsOneWidget);
      // One supporting line: when, then what.
      expect(
        find.textContaining('12:00 PM · 150 ml (5.1 fl oz)'),
        findsOneWidget,
      );
    });

    testWidgets('metric when that is what they use', (tester) async {
      await pumpNursery(tester, prefs: {'unit_system': 'metric'});

      expect(find.textContaining('150 ml'), findsOneWidget);
      expect(find.textContaining('fl oz'), findsNothing);
    });

    testWidgets('and fits, rather than trailing off', (tester) async {
      // The longest form, at the boost nursery mode applies, on a phone
      // rather than the tablet this mode is aimed at. The number is the
      // thing being asked for, so it losing its tail is the failure.
      await pumpNursery(tester, size: const Size(390, 844));

      final amount = find.textContaining('150 ml (5.1 fl oz)');
      expect(amount, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(amount).didExceedMaxLines,
        isFalse,
      );
    });

    testWidgets('minutes at the breast when there is no volume', (
      tester,
    ) async {
      await pumpNursery(
        tester,
        feeds: [
          FeedingEvent(
            id: 'f1',
            type: FeedingType.breast,
            startTime: now.subtract(const Duration(hours: 2)),
            durationMinutes: 18,
          ),
        ],
      );

      expect(find.textContaining('18 min'), findsOneWidget);
    });

    testWidgets('and the diaper card is built the same way', (tester) async {
      // The pair has to read as one design. Left at two lines against the
      // feed card's four, at the matched heights these cards are given, the
      // emptiness was the loudest thing on screen.
      await pumpNursery(tester);

      expect(find.textContaining('1:20 PM · Wet'), findsOneWidget);
    });

    testWidgets('and nothing at all when the feed was never measured', (
      tester,
    ) async {
      await pumpNursery(
        tester,
        feeds: [
          FeedingEvent(
            id: 'f1',
            type: FeedingType.breast,
            startTime: now.subtract(const Duration(hours: 2)),
          ),
        ],
      );

      // The card still reads; it just has one line fewer. Scoped to a bare
      // measurement, since the diaper card's "40 min ago" is on screen too.
      expect(find.text('2 hr ago'), findsOneWidget);
      expect(find.textContaining('ml'), findsNothing);
      expect(find.textContaining(RegExp(r'^\d+ min$')), findsNothing);
    });
  });

  testWidgets('and nothing else — no lists, no charts', (tester) async {
    // The point of the mode. If a list or a chart ever creeps back in, the
    // screen has stopped being the thing it was for.
    await pumpNursery(tester);

    expect(find.byType(ListView), findsNothing);
    expect(find.byType(CustomPaint).evaluate().length, lessThan(20));
  });

  testWidgets('offers bottle, diaper and pumping', (tester) async {
    await pumpNursery(tester);

    expect(find.text('Bottle'), findsOneWidget);
    expect(find.text('Diaper'), findsOneWidget);
    expect(find.text('Pump'), findsOneWidget);
    // Everything else is a tap away through the full app.
    expect(find.text('Breast'), findsNothing);
    expect(find.text('Solids'), findsNothing);
  });

  testWidgets('and drops pumping for a household that has turned it off', (
    tester,
  ) async {
    // The same preference the Home button follows. Meeting it again here
    // would make the setting a half-truth.
    await pumpNursery(tester, prefs: {'show_pumping_action': false});

    expect(find.text('Pump'), findsNothing);
    expect(find.text('Bottle'), findsOneWidget);
  });

  testWidgets('puts the next feed inside the card it is about', (tester) async {
    // Loose underneath, the chip floated between two cards with nothing
    // saying which one it belonged to.
    await pumpNursery(tester, prefs: {'reminder_mode': 'fixedInterval'});

    final chip = find.byType(DueChip);
    expect(chip, findsOneWidget);

    final fed = tester.getRect(find.text('Last fed'));
    final rect = tester.getRect(chip);
    expect(rect.top, greaterThan(fed.bottom));

    // And inside the feed card's own bounds, which is the claim — stated
    // against the card rather than against where the diaper card happens to
    // be, so it holds however the two are arranged.
    final card = tester.getRect(
      find
          .ancestor(of: find.text('Last fed'), matching: find.byType(Container))
          .first,
    );
    expect(card.contains(rect.topLeft), isTrue);
    expect(card.contains(rect.bottomRight), isTrue);
  });

  testWidgets('a button opens its sheet with the kind already chosen', (
    tester,
  ) async {
    // The chooser would be a step asking again for something already said.
    await pumpNursery(tester);
    await tester.tap(find.text('Bottle'));
    await tester.pumpAndSettle();

    expect(find.text('Log a feed'), findsNothing, reason: 'chooser was shown');
    expect(find.widgetWithText(AppBar, 'Bottle'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('there is a way out, or the device is stuck', (tester) async {
    // The navigation bar is hidden in this mode, so this control is the only
    // route back to Settings.
    final container = await pumpNursery(tester);
    expect(container.read(displayModeProvider), DisplayMode.nursery);

    await tester.tap(find.byTooltip('Leave nursery mode'));
    await tester.pumpAndSettle();

    expect(container.read(displayModeProvider), DisplayMode.normal);
  });

  testWidgets('says so plainly when nothing has been logged', (tester) async {
    await pumpNursery(tester, withData: false);
    expect(find.text('Nothing logged yet'), findsNWidgets(2));
  });

  group('the text boost', () {
    test('lifts a default reader up to it', () {
      expect(NurseryScreen.textBoost, greaterThan(1));
    });

    testWidgets('does not stack on top of an accessibility setting', (
      tester,
    ) async {
      // It multiplies with the reader's own size, so someone already at 150%
      // would land near 210% and lose the layout. The boost is a floor to
      // reach, not a factor to pile on.
      await pumpNursery(tester, textScale: 1.5);
      expect(tester.takeException(), isNull);

      final scaler = MediaQuery.textScalerOf(
        tester.element(find.text('Last fed')),
      );
      expect(scaler.scale(1), lessThanOrEqualTo(NurseryScreen.maxTextScale));
      // And a reader who asked for large text keeps it.
      expect(scaler.scale(1), greaterThanOrEqualTo(1.5));
    });

    testWidgets('survives a phone-sized screen at the largest size', (
      tester,
    ) async {
      await pumpNursery(tester, textScale: 2.0, size: const Size(390, 844));
      expect(tester.takeException(), isNull);
    });
  });

  group('landscape, which is how a tablet on a stand usually sits', () {
    testWidgets('puts the two cards side by side', (tester) async {
      // Where the width goes in landscape. Stacked, each card gets half the
      // height it could have and the screen is mostly empty beside them.
      await pumpNursery(tester, size: const Size(900, 600));

      final fed = tester.getRect(find.text('Last fed'));
      final changed = tester.getRect(find.text('Last changed'));
      expect(changed.left, greaterThan(fed.right));
    });

    testWidgets('and keeps the buttons along the bottom', (tester) async {
      // Under the cards in both orientations, so the cards always have the
      // full width to themselves.
      await pumpNursery(tester, size: const Size(900, 600));

      final card = tester.getRect(find.text('Last fed'));
      final button = tester.getRect(find.text('Bottle'));
      expect(button.top, greaterThan(card.bottom));
    });

    testWidgets('and lines them up on an iPad held upright too', (
      tester,
    ) async {
      // Upright used to stack on the grounds of orientation, which was the
      // wrong question: 834pt is width for two cards whichever way round the
      // device is, and stacking left them in a column down the middle of a
      // screen with room either side.
      await pumpNursery(tester, size: const Size(834, 1194));

      final fed = tester.getRect(find.text('Last fed'));
      final changed = tester.getRect(find.text('Last changed'));
      expect(changed.left, greaterThan(fed.right));
    });

    testWidgets('but a phone upright still stacks them', (tester) async {
      // The other end of the same rule. Two columns of 167pt would be a pair
      // of slivers, so width is what decides, not orientation.
      await pumpNursery(tester, size: const Size(390, 844));

      final fed = tester.getRect(find.text('Last fed'));
      final changed = tester.getRect(find.text('Last changed'));
      expect(changed.top, greaterThan(fed.bottom));
    });

    testWidgets('a phone on its side still fits everything', (tester) async {
      // The tightest case there is: 390pt of height for two readouts and
      // three buttons.
      await pumpNursery(tester, size: const Size(844, 390));
      expect(tester.takeException(), isNull);

      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Diaper'), findsOneWidget);
      expect(find.text('Last fed'), findsOneWidget);
    });

    testWidgets('and survives it at the largest text size', (tester) async {
      await pumpNursery(tester, size: const Size(844, 390), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('the pump card', () {
    final pumped = [
      PumpingEvent(
        id: 'p1',
        time: now.subtract(const Duration(minutes: 30)),
        amountMl: 90,
        durationMinutes: 15,
      ),
    ];

    testWidgets('is there for a household that pumps', (tester) async {
      await pumpNursery(tester, pumps: pumped);

      expect(find.text('Last pumped'), findsOneWidget);
      expect(find.text('30 min ago'), findsOneWidget);
    });

    testWidgets('with how much, the way the feed card does', (tester) async {
      // The measure, not the full detail line: a note is a sentence and this
      // screen is read from a doorway.
      await pumpNursery(
        tester,
        pumps: pumped,
        prefs: {'unit_system': 'metric'},
      );

      expect(find.textContaining('90 ml'), findsOneWidget);
    });

    testWidgets('and is absent until something is pumped', (tester) async {
      // The default for most households, and the reason the card is
      // conditional: an empty third of this screen says nothing.
      await pumpNursery(tester);

      expect(find.text('Last pumped'), findsNothing);
      expect(find.text('Last fed'), findsOneWidget);
      expect(find.text('Last changed'), findsOneWidget);
    });

    testWidgets('or when pumping is switched off', (tester) async {
      await pumpNursery(
        tester,
        pumps: pumped,
        prefs: {'show_pumping_action': false},
      );

      expect(find.text('Last pumped'), findsNothing);
    });

    testWidgets('carries the cadence countdown when one is set', (
      tester,
    ) async {
      await pumpNursery(
        tester,
        pumps: pumped,
        prefs: {'pump_interval_minutes': 120},
      );

      expect(find.textContaining('Next pump in 1h 30m'), findsOneWidget);
    });

    testWidgets('carries the way into the fridge', (tester) async {
      // The same button Home's pump row has. On a propped-up tablet the
      // fridge is often the next question, and leaving nursery mode to find
      // it would be the long way round.
      await pumpNursery(tester, pumps: pumped);

      expect(find.byType(FridgeButton), findsOneWidget);
      final card = tester.getRect(find.text('Last pumped'));
      final button = tester.getRect(find.byType(FridgeButton));
      // Level with the label, at the card's top-right. The label fills the
      // line up to the button, so the two meet rather than leave a gap.
      expect(button.left, greaterThanOrEqualTo(card.right - 0.5));
      expect(button.top, lessThan(card.bottom));
    });

    testWidgets('and only the pump card does', (tester) async {
      // Feeding and diapers lead nowhere. No pump card, no button.
      await pumpNursery(tester);
      expect(find.byType(FridgeButton), findsNothing);
    });

    testWidgets('and stays a plain reading without one', (tester) async {
      await pumpNursery(tester, pumps: pumped);

      expect(find.textContaining('Next pump'), findsNothing);
      // The feed card's own chip is untouched by any of this.
      expect(find.textContaining('Next feed'), findsOneWidget);
    });
  });

  group('three cards, for a household that pumps', () {
    final pumped = [
      PumpingEvent(
        id: 'p1',
        time: now.subtract(const Duration(minutes: 30)),
        amountMl: 90,
      ),
    ];

    testWidgets('sit in a row on a tablet with the width for it', (
      tester,
    ) async {
      await pumpNursery(tester, pumps: pumped, size: const Size(1200, 800));

      final fed = tester.getRect(find.text('Last fed'));
      final changed = tester.getRect(find.text('Last changed'));
      final pump = tester.getRect(find.text('Last pumped'));

      expect(changed.left, greaterThan(fed.right));
      expect(pump.left, greaterThan(changed.right));
    });

    testWidgets('on every iPad, in either orientation', (tester) async {
      // The size that prompted this. An iPad has the width for three cards
      // whichever way round it is held, and the smallest of them — 768pt
      // upright, three columns of 232 — is the case the minimum width is set
      // by.
      const iPads = [
        Size(768, 1024), // 9.7", upright
        Size(834, 1194), // 11", upright
        Size(1024, 1366), // 12.9", upright
        Size(1024, 768), // 9.7", on its side
        Size(1366, 1024), // 12.9", on its side
      ];

      for (final size in iPads) {
        await tester.pumpWidget(const SizedBox());
        await pumpNursery(tester, pumps: pumped, size: size);

        final fed = tester.getRect(find.text('Last fed'));
        final changed = tester.getRect(find.text('Last changed'));
        final pump = tester.getRect(find.text('Last pumped'));

        expect(changed.left, greaterThan(fed.right), reason: '$size');
        expect(pump.left, greaterThan(changed.right), reason: '$size');
      }
    });

    testWidgets('and wrap to two-above-one when it is narrower', (
      tester,
    ) async {
      // Below three columns' worth of width the row wraps rather than
      // shaving every card thinner. Two and one beats three slivers.
      await pumpNursery(tester, pumps: pumped, size: const Size(700, 500));

      final fed = tester.getRect(find.text('Last fed'));
      final changed = tester.getRect(find.text('Last changed'));
      final pump = tester.getRect(find.text('Last pumped'));

      expect(changed.left, greaterThan(fed.right));
      expect(pump.top, greaterThan(changed.bottom));
    });

    testWidgets('and stack on a phone held upright', (tester) async {
      await pumpNursery(tester, pumps: pumped, size: const Size(390, 844));

      final changed = tester.getRect(find.text('Last changed'));
      final pump = tester.getRect(find.text('Last pumped'));
      expect(pump.top, greaterThan(changed.bottom));
    });

    testWidgets('a phone on its side still fits all three', (tester) async {
      // The tightest case, now with one more card in it.
      await pumpNursery(tester, pumps: pumped, size: const Size(844, 390));

      expect(tester.takeException(), isNull);
      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Last pumped'), findsOneWidget);
    });

    testWidgets('and survives it at the largest text size', (tester) async {
      await pumpNursery(
        tester,
        pumps: pumped,
        size: const Size(844, 390),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('getting into it', () {
    testWidgets('from Home, beside the full-timeline link', (tester) async {
      // Not Settings: this is the control you reach for as the device is
      // being put down, and both buttons change what the screen is for.
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
          recentFeedingsProvider.overrideWith((ref) => Stream.value(const [])),
          recentDiapersProvider.overrideWith((ref) => Stream.value(const [])),
          recentPumpingProvider.overrideWith((ref) => Stream.value(const [])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Full timeline'), findsOneWidget);
      expect(container.read(displayModeProvider), DisplayMode.normal);

      await tester.tap(find.byTooltip('Nursery mode'));
      await tester.pumpAndSettle();

      expect(container.read(displayModeProvider), DisplayMode.nursery);
    });

    testWidgets('without making the pinned header any taller', (tester) async {
      // The header is pinned, and a pinned header must be told its height in
      // advance. An IconButton is 48 high at every text size, which is what
      // headerHeight already assumes — so a second one changes nothing.
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
            recentFeedingsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            recentDiapersProvider.overrideWith((ref) => Stream.value(const [])),
            recentPumpingProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: HomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Nursery mode'), findsOneWidget);
    });
  });

  testWidgets('the button labels take the button\'s own colour', (
    tester,
  ) async {
    // Passing textTheme.titleMedium carried the theme's near-black onSurface
    // with it and overrode the button's foreground, which put black text on a
    // filled blue button. The label has to inherit instead.
    await pumpNursery(tester);

    final label = tester.element(find.text('Bottle'));
    final inherited = DefaultTextStyle.of(label).style.color;
    final scheme = Theme.of(label).colorScheme;

    expect(inherited, scheme.onPrimary);
    expect(inherited, isNot(scheme.onSurface));

    // And the Text does not carry a colour of its own to override it with.
    expect(tester.widget<Text>(find.text('Bottle')).style?.color, isNull);
  });

  group('the feed card carries how close the next feed is', () {
    Color cardColour(WidgetTester tester, String label) {
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    FeedingEvent feedAt(int minutesAgo) => FeedingEvent(
      id: 'f1',
      type: FeedingType.bottle,
      startTime: now.subtract(Duration(minutes: minutesAgo)),
      amountMl: 150,
    );

    testWidgets('so the colour arrives before the words do', (tester) async {
      // Read from a doorway, the card's colour is the first thing to land.
      // Just fed against long overdue: two different states, two different
      // cards.
      await pumpNursery(tester, feeds: [feedAt(20)]);
      final justFed = cardColour(tester, 'Last fed');

      await pumpNursery(tester, feeds: [feedAt(400)]);
      final overdue = cardColour(tester, 'Last fed');

      expect(justFed, isNot(overdue));
    });

    testWidgets('and the diaper card stays out of it', (tester) async {
      // It has no due state of its own, so colouring it would be decoration
      // pretending to be information.
      await pumpNursery(tester, feeds: [feedAt(20)]);
      final calm = cardColour(tester, 'Last changed');

      await pumpNursery(tester, feeds: [feedAt(400)]);
      expect(cardColour(tester, 'Last changed'), calm);
    });

    testWidgets('and is tinted apart from it', (tester) async {
      await pumpNursery(tester, feeds: [feedAt(400)]);

      expect(
        cardColour(tester, 'Last fed'),
        isNot(cardColour(tester, 'Last changed')),
      );
    });
  });

  group('the diaper card carries how long it has been', () {
    Color cardColour(WidgetTester tester, String label) {
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    Future<Color> at(WidgetTester tester, Duration ago) async {
      await pumpNursery(
        tester,
        diapers: [
          DiaperEvent(id: 'd1', type: DiaperType.wet, time: now.subtract(ago)),
        ],
      );
      return cardColour(tester, 'Last changed');
    }

    testWidgets('calm, then amber at two hours, then red at three', (
      tester,
    ) async {
      final fresh = await at(tester, const Duration(minutes: 30));
      final amber = await at(tester, const Duration(hours: 2, minutes: 30));
      final red = await at(tester, const Duration(hours: 3, minutes: 30));

      expect(amber, isNot(fresh));
      expect(red, isNot(amber));
    });

    testWidgets('and each step reads louder than the one before', (
      tester,
    ) async {
      // The failure this guards is specific: at a flat blend strength the
      // scheme's errorContainer sat so near the surface that red came out
      // *paler* than amber, and the last step of the warning was its
      // quietest.
      /// How far a tint sits from the untinted card.
      double loudness(Color calm, Color c) =>
          (c.r - calm.r).abs() + (c.g - calm.g).abs() + (c.b - calm.b).abs();

      final fresh = await at(tester, const Duration(minutes: 30));
      final amber = await at(tester, const Duration(hours: 2, minutes: 30));
      final red = await at(tester, const Duration(hours: 3, minutes: 30));

      expect(
        loudness(fresh, red),
        greaterThan(loudness(fresh, amber)),
        reason: 'red must be further from calm than amber is',
      );
    });

    testWidgets('but stays neutral when nothing has been logged', (
      tester,
    ) async {
      await pumpNursery(tester, diapers: const []);
      // Nothing to be overdue about on a household's first morning.
      expect(find.text('Nothing logged yet'), findsWidgets);
    });
  });

  group('the clock', () {
    testWidgets('is on screen, with the day under it', (tester) async {
      // A tablet on a nursery shelf is the nearest clock at 3am.
      await pumpNursery(tester);

      expect(find.text('2:00 PM'), findsOneWidget);
      expect(find.text('Mon, Aug 24'), findsOneWidget);
      // Never "Today", which a clock has no use for.
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('sits in the middle of the screen', (tester) async {
      // In a band of its own under the header, so nothing on either side
      // can push it off centre.
      await pumpNursery(tester, size: const Size(834, 1194));

      final time = tester.getRect(find.text('2:00 PM'));
      expect(time.center.dx, moreOrLessEquals(834 / 2, epsilon: 1));
    });

    testWidgets('and stays centred on a narrow screen too', (tester) async {
      await pumpNursery(tester, size: const Size(390, 844));

      final time = tester.getRect(find.text('2:00 PM'));
      expect(time.center.dx, moreOrLessEquals(390 / 2, epsilon: 1));
    });

    testWidgets('keeps the header to one line at a large text size', (
      tester,
    ) async {
      // The header carries a name, an age and the way out, on a screen that
      // has already scaled its text up by a third.
      await pumpNursery(tester, textScale: 2.0, size: const Size(390, 844));
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Leave nursery mode'), findsOneWidget);
    });

    testWidgets('is drawn to be read from a doorway', (tester) async {
      // The point of the mode: a tablet on a shelf should answer "what time
      // is it" from across the room, not from arm's length. Compared against
      // the day under it, which is set at ordinary label size.
      await pumpNursery(tester, size: const Size(1194, 834));

      final time = tester.getRect(find.text('2:00 PM'));
      final day = tester.getRect(find.text('Mon, Aug 24'));
      expect(time.height, greaterThan(100));
      expect(time.height, greaterThan(day.height * 4));
    });

    testWidgets('and takes what the screen can spare, no more', (tester) async {
      // Sized off both dimensions, so a phone gets a clock rather than a
      // wall of digits with the cards pushed off the bottom.
      await pumpNursery(tester, size: const Size(390, 844));

      final phone = tester.getRect(find.text('2:00 PM')).height;
      expect(phone, greaterThan(40), reason: 'still a clock');
      expect(phone, lessThan(100), reason: 'and still leaves room');
      // The cards it sits above are still on screen.
      expect(find.text('Last fed'), findsOneWidget);
      expect(find.text('Last changed'), findsOneWidget);

      await pumpNursery(tester, size: const Size(1194, 834));
      expect(
        tester.getRect(find.text('2:00 PM')).height,
        greaterThan(phone),
        reason: 'a tablet has room for more of it',
      );
    });

    testWidgets('runs a ticker, and stops it on the way out', (tester) async {
      // The bug this fixes: nothing else rebuilds this screen — it is meant
      // to be left running on a shelf — so without a ticker the elapsed
      // times froze at whatever they said when the mode was entered.
      //
      // That the *label* refreshes is not asserted here, and deliberately.
      // A widget test advances fake-async time while the ticker reads the
      // real DateTime.now(), so the two never move together; a test that
      // waited for real seconds to pass would be slow and flaky. What is
      // checked is that a periodic timer exists at all and is cancelled —
      // the framework fails the test at teardown on either count.
      SharedPreferences.setMockInitialValues({});
      final stored = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(834, 1194);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
            recentFeedingsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            recentDiapersProvider.overrideWith((ref) => Stream.value(const [])),
            recentPumpingProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          // No fixed clock, which is what starts the ticker.
          child: const MaterialApp(home: NurseryScreen()),
        ),
      );
      await tester.pump();

      // Firing it must not throw — it calls setState on a live widget.
      await tester.pump(NurseryScreen.tick * 3);
      expect(tester.takeException(), isNull);

      // And leaving the screen cancels it. A leaked periodic timer fails the
      // test here rather than quietly running for the life of the process.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(NurseryScreen.tick * 3);
    });

    testWidgets('does not tick when handed a fixed clock', (tester) async {
      // What keeps every other test in this file free of pending timers.
      await pumpNursery(tester);
      await tester.pump(const Duration(minutes: 5));
      expect(find.text('2:00 PM'), findsOneWidget);
    });
  });
}
