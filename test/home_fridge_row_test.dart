import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/common/banded_track.dart';
import 'package:baby_app/features/fridge/bottle_gauge.dart';
import 'package:baby_app/features/fridge/fridge_button.dart';
import 'package:baby_app/features/home/home_status_card.dart';

/// The fridge row on the Home status card: what is in it, and the
/// way in. Its own row rather than a button on the pump row, where it was.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 4, 14);

  FridgeBottle bottle(String id, int hoursAgo, double ml) => FridgeBottle(
    id: id,
    filledAt: now.subtract(Duration(hours: hoursAgo)),
    amountMl: ml,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    List<FridgeBottle> bottles = const [],
    Map<String, Object> prefs = const {},
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues({'unit_system': 'metric', ...prefs});
    final stored = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          recentFeedingsProvider.overrideWith((ref) => Stream.value([])),
          recentDiapersProvider.overrideWith((ref) => Stream.value([])),
          recentPumpingProvider.overrideWith((ref) => Stream.value([])),
          fridgeBottlesProvider.overrideWith((ref) => Stream.value(bottles)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: SingleChildScrollView(child: HomeStatusCard(now: now)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The colour of the dot beside the row's label, or null for none. The
  /// only row in these fixtures that can have one.
  Color? dot(WidgetTester tester) {
    final found = find.byKey(const ValueKey('alert-dot'));
    if (found.evaluate().isEmpty) return null;
    final box = tester.widget<Container>(found).decoration! as BoxDecoration;
    return box.color;
  }

  testWidgets('says how many and how much, with the way in', (tester) async {
    await pumpCard(tester, bottles: [bottle('a', 5, 90), bottle('b', 2, 60)]);
    expect(find.text('FRIDGE'), findsOneWidget);
    expect(find.text('2 bottles · 150\u00a0ml'), findsOneWidget);
    // Drawn as well as counted, up to three: one small bottle each.
    expect(find.byKey(const ValueKey('home-bottle-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-bottle-b')), findsOneWidget);
    expect(find.byType(FridgeButton), findsOneWidget);
    // An arrow, not a second fridge beside the row's own.
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byIcon(FridgeButton.icon), findsOneWidget);
    expect(find.byTooltip('In the fridge'), findsOneWidget);
    expect(dot(tester), isNull);
  });

  testWidgets('is there without pumping, and says when it is empty', (
    tester,
  ) async {
    // Formula and whole milk go in the fridge too, so a household that
    // never pumps still has one — and "Empty" is an answer.
    await pumpCard(tester);
    expect(find.text('Empty'), findsOneWidget);
    expect(find.byType(FridgeButton), findsOneWidget);
  });

  testWidgets('and is gone with the fridge switched off', (tester) async {
    await pumpCard(
      tester,
      bottles: [bottle('a', 5, 90)],
      prefs: {'show_fridge': false},
    );
    expect(find.text('FRIDGE'), findsNothing);
    expect(find.byType(FridgeButton), findsNothing);
  });

  testWidgets('names the most pressing bottle, and turns amber then red', (
    tester,
  ) async {
    await pumpCard(tester, bottles: [bottle('a', 50, 90), bottle('b', 2, 60)]);
    expect(find.text('1 is 2+ days old'), findsOneWidget);
    final context = tester.element(find.text('FRIDGE'));
    expect(dot(tester), warningInks(context).soon);

    await tester.pumpWidget(const SizedBox());
    await pumpCard(
      tester,
      bottles: [bottle('a', 100, 90), bottle('b', 80, 60)],
    );
    // Past drink-by outranks merely old.
    expect(find.text('1 is past drink-by'), findsOneWidget);
    final again = tester.element(find.text('FRIDGE'));
    expect(dot(tester), warningInks(again).overdue);
  });

  testWidgets('says one bottle as one', (tester) async {
    await pumpCard(tester, bottles: [bottle('a', 5, 90)]);
    expect(find.byKey(const ValueKey('home-bottle-a')), findsOneWidget);
    expect(find.text('1 bottle · 90\u00a0ml'), findsOneWidget);
  });

  testWidgets('draws three, oldest first', (tester) async {
    await pumpCard(
      tester,
      bottles: [
        bottle('new', 1, 60),
        bottle('old', 9, 90),
        bottle('mid', 5, 30),
      ],
    );
    double x(String id) =>
        tester.getRect(find.byKey(ValueKey('home-bottle-$id'))).left;
    expect(x('old'), lessThan(x('mid')));
    expect(x('mid'), lessThan(x('new')));
    expect(find.text('3 bottles · 180\u00a0ml'), findsOneWidget);
  });

  testWidgets('but past three, gives only the count', (tester) async {
    await pumpCard(
      tester,
      bottles: [for (var i = 0; i < 4; i++) bottle('b$i', i + 1, 60)],
    );
    expect(find.text('4 bottles · 240\u00a0ml'), findsOneWidget);
    expect(find.byType(BottleGauge), findsNothing);
  });

  testWidgets('and fits a small phone at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpCard(
      tester,
      bottles: [bottle('a', 5, 90), bottle('b', 3, 60), bottle('c', 2, 120)],
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BottleGauge), findsNWidgets(3));
  });
}
