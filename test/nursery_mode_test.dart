import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/home_prefs.dart';
import 'package:baby_app/features/home/home_screen.dart';
import 'package:baby_app/features/home/nursery_screen.dart';

/// The screen for a tablet propped on a shelf (#29).
///
/// Not Home scaled up: two readouts, three buttons, and nothing else — read
/// from across a room and tapped while holding a baby.
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
  }) async {
    SharedPreferences.setMockInitialValues({'display_mode': 'nursery'});
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
            withData
                ? [
                    FeedingEvent(
                      id: 'f1',
                      type: FeedingType.bottle,
                      startTime: now.subtract(const Duration(hours: 2)),
                      amountMl: 150,
                    ),
                  ]
                : const [],
          ),
        ),
        recentDiapersProvider.overrideWith(
          (ref) => Stream.value(
            withData
                ? [
                    DiaperEvent(
                      id: 'd1',
                      type: DiaperType.wet,
                      time: now.subtract(const Duration(minutes: 40)),
                    ),
                  ]
                : const [],
          ),
        ),
        recentPumpingProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: NurseryScreen(now: now),
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

  testWidgets('and nothing else — no lists, no charts', (tester) async {
    // The point of the mode. If a list or a chart ever creeps back in, the
    // screen has stopped being the thing it was for.
    await pumpNursery(tester);

    expect(find.byType(ListView), findsNothing);
    expect(find.byType(CustomPaint).evaluate().length, lessThan(20));
  });

  testWidgets('offers exactly bottle, breast and diaper', (tester) async {
    await pumpNursery(tester);

    expect(find.text('Bottle'), findsOneWidget);
    expect(find.text('Breast'), findsOneWidget);
    expect(find.text('Diaper'), findsOneWidget);
    // Solids and pumping are not nursery-at-3am things.
    expect(find.text('Solids'), findsNothing);
    expect(find.text('Pumping'), findsNothing);
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
      await pumpNursery(
        tester,
        textScale: 2.0,
        size: const Size(390, 844),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('landscape, which is how a tablet on a stand usually sits', () {
    testWidgets('puts the buttons beside the readouts, not under them', (
      tester,
    ) async {
      // Stacked in landscape the buttons are squeezed into a strip along the
      // bottom of a mostly empty screen.
      await pumpNursery(tester, size: const Size(900, 600));

      final readout = tester.getRect(find.text('Last fed'));
      final button = tester.getRect(find.text('Bottle'));
      expect(button.left, greaterThan(readout.right));
    });

    testWidgets('and stacks them again in portrait', (tester) async {
      await pumpNursery(tester, size: const Size(834, 1194));

      final readout = tester.getRect(find.text('Last fed'));
      final button = tester.getRect(find.text('Bottle'));
      expect(button.top, greaterThan(readout.bottom));
    });

    testWidgets('a phone on its side still fits everything', (tester) async {
      // The tightest case there is: 390pt of height for two readouts and
      // three buttons.
      await pumpNursery(tester, size: const Size(844, 390));
      expect(tester.takeException(), isNull);

      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Breast'), findsOneWidget);
      expect(find.text('Diaper'), findsOneWidget);
      expect(find.text('Last fed'), findsOneWidget);
    });

    testWidgets('and survives it at the largest text size', (tester) async {
      await pumpNursery(tester, size: const Size(844, 390), textScale: 2.0);
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
            recentFeedingsProvider.overrideWith((ref) => Stream.value(const [])),
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
}
