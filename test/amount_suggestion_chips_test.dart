import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/format/volume_entry.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/feeding/amount_suggestion_chips.dart';
import 'package:baby_app/features/feeding/amount_suggestion_providers.dart';
import 'package:baby_app/features/feeding/amount_suggestions.dart';
import 'package:baby_app/features/feeding/feeding_quick_log.dart';
import 'package:baby_app/features/pumping/pumping_format.dart';

/// The one-tap amounts under the bottle form's field (#31).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const suggestions = [
    AmountSuggestion(90, AmountSource.bottle),
    AmountSuggestion(120, AmountSource.bottle),
    AmountSuggestion(130, AmountSource.pump),
  ];

  Future<void> pumpChips(
    WidgetTester tester, {
    List<AmountSuggestion> offered = suggestions,
    VolumeUnit unit = VolumeUnit.ml,
    void Function(double)? onPick,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bottleAmountSuggestionsProvider.overrideWithValue(offered)],
        child: MaterialApp(
          home: Scaffold(
            body: AmountSuggestionChips(unit: unit, onPick: onPick ?? (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the chips', () {
    testWidgets('offer each amount in the unit the field is showing', (
      tester,
    ) async {
      await pumpChips(tester);
      expect(find.text('90 ml'), findsOneWidget);
      expect(find.text('120 ml'), findsOneWidget);
      expect(find.text('130 ml'), findsOneWidget);
    });

    testWidgets('follow the field into fluid ounces', (tester) async {
      await pumpChips(tester, unit: VolumeUnit.flOz);
      expect(find.text('4.1 fl oz'), findsOneWidget);
      expect(find.text('120 ml'), findsNothing);
    });

    testWidgets('hand back exact millilitres, not the rounded label', (
      tester,
    ) async {
      // The label says "4.1"; parsing that back would be 121.3.
      final picked = <double>[];
      await pumpChips(tester, unit: VolumeUnit.flOz, onPick: picked.add);
      await tester.tap(find.text('4.1 fl oz'));
      expect(picked, [120]);
    });

    testWidgets('mark the one that came from the last pump', (tester) async {
      await pumpChips(tester);
      final marked = find.descendant(
        of: find.widgetWithText(ActionChip, '130 ml'),
        matching: find.byIcon(PumpingFormat.icon),
      );
      expect(marked, findsOneWidget);
      // And only that one — the others are habit, not milk in the fridge.
      expect(find.byIcon(PumpingFormat.icon), findsOneWidget);
    });

    testWidgets('wrap onto a second line rather than overflowing a phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Fluid ounces make the widest labels.
      await pumpChips(
        tester,
        unit: VolumeUnit.flOz,
        offered: const [
          AmountSuggestion(60, AmountSource.bottle),
          AmountSuggestion(90, AmountSource.bottle),
          AmountSuggestion(120, AmountSource.bottle),
          AmountSuggestion(150, AmountSource.bottle),
          AmountSuggestion(180, AmountSource.pump),
        ],
      );

      expect(find.byType(ActionChip), findsNWidgets(5));
      final rects = tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((c) => tester.getRect(find.byWidget(c)))
          .toList();
      expect(
        rects.every((r) => r.left >= 0 && r.right <= 390),
        isTrue,
        reason: 'every chip stays on screen',
      );
      expect(
        rects.map((r) => r.top).toSet().length,
        greaterThan(1),
        reason: 'five of them need a second line',
      );
    });

    testWidgets('render nothing at all when there is nothing to suggest', (
      tester,
    ) async {
      await pumpChips(tester, offered: const []);
      expect(find.byType(ActionChip), findsNothing);
    });
  });

  group('in the bottle sheet', () {
    Future<void> openBottleSheet(WidgetTester tester) async {
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
            bottleAmountSuggestionsProvider.overrideWithValue(suggestions),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () =>
                        showFeedingQuickLog(context, type: FeedingType.bottle),
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

    String amountText(WidgetTester tester) => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Amount'))
        .controller!
        .text;

    testWidgets('sit under the amount field, above the time', (tester) async {
      await openBottleSheet(tester);
      final field = tester.getRect(find.widgetWithText(TextField, 'Amount'));
      final chips = tester.getRect(find.byType(ActionChip).first);
      expect(chips.top, greaterThan(field.top));
    });

    testWidgets('fill the field when tapped', (tester) async {
      await openBottleSheet(tester);
      expect(amountText(tester), isEmpty);
      await tester.tap(find.text('120 ml'));
      await tester.pump();
      expect(amountText(tester), '120');
    });
  });

  group('what the provider draws on', () {
    final bottle = FeedingEvent(
      id: 'f',
      type: FeedingType.bottle,
      startTime: DateTime(2026, 8, 30, 6),
      amountMl: 120,
    );
    final freshPump = PumpingEvent(
      id: 'p',
      time: DateTime(2026, 8, 30, 9),
      amountMl: 130,
    );

    Future<List<AmountSuggestion>> suggestionsWith({
      required bool pumpingShown,
    }) async {
      SharedPreferences.setMockInitialValues({
        'show_pumping_action': pumpingShown,
      });
      final stored = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          recentFeedingsProvider.overrideWith((ref) => Stream.value([bottle])),
          recentPumpingProvider.overrideWith(
            (ref) => Stream.value([freshPump]),
          ),
        ],
      );
      addTearDown(container.dispose);
      // The providers are auto-dispose: a bare read would build and tear
      // down again before the streams ever emit. The pump stream is listened
      // to here whether or not the suggestions want it, so that both have
      // certainly emitted by the time we read — otherwise a missing gate
      // would pass this by reading a pump stream that had not arrived yet
      // rather than one deliberately left out.
      container.listen(bottleAmountSuggestionsProvider, (_, _) {});
      container.listen(recentPumpingProvider, (_, _) {});
      await container.read(recentFeedingsProvider.future);
      await container.read(recentPumpingProvider.future);
      return container.read(bottleAmountSuggestionsProvider);
    }

    test('the last pump, alongside the bottles', () async {
      expect(await suggestionsWith(pumpingShown: true), const [
        AmountSuggestion(120, AmountSource.bottle),
        AmountSuggestion(130, AmountSource.pump),
      ]);
    });

    test('bottles only, once pumping is switched off', () async {
      // Same data either way, so this fails if the gate stops working
      // rather than passing on an empty result.
      expect(await suggestionsWith(pumpingShown: false), const [
        AmountSuggestion(120, AmountSource.bottle),
      ]);
    });
  });
}
