import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/features/diaper/diaper_quick_log.dart';

/// The diaper sheet's poop size, which is offered but not demanded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openSheet(WidgetTester tester, {DiaperEvent? existing}) async {
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
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showDiaperQuickLog(context, existing: existing),
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

  /// Which size the picker has selected, or null for none.
  PoopSize? selectedSize(WidgetTester tester) {
    final picker = find.byType(SegmentedButton<PoopSize>);
    if (picker.evaluate().isEmpty) return null;
    final selected = tester
        .widget<SegmentedButton<PoopSize>>(picker)
        .selected;
    return selected.isEmpty ? null : selected.first;
  }

  testWidgets('a new sheet starts on wet, with nothing to size', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.byType(SegmentedButton<PoopSize>), findsNothing);
  });

  testWidgets('choosing dirty chooses small with it', (tester) async {
    // Small is the common one, so the usual log is one tap rather than two.
    await openSheet(tester);
    await tester.tap(find.text('Dirty'));
    await tester.pumpAndSettle();

    expect(selectedSize(tester), PoopSize.small);
  });

  testWidgets('and so does choosing both', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Wet + Dirty'));
    await tester.pumpAndSettle();

    expect(selectedSize(tester), PoopSize.small);
  });

  testWidgets('it is still a default, not a requirement', (tester) async {
    // Tapping the chosen size again clears it, as it always did.
    await openSheet(tester);
    await tester.tap(find.text('Dirty'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Small'));
    await tester.pumpAndSettle();

    expect(selectedSize(tester), isNull);
  });

  testWidgets('a size already chosen is not overwritten', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Dirty'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();

    // Through wet, which clears it, and back — the default applies again
    // because there is nothing to keep.
    await tester.tap(find.text('Wet + Dirty'));
    await tester.pumpAndSettle();
    expect(selectedSize(tester), PoopSize.large);
  });

  testWidgets('opening an old entry does not invent a size for it', (
    tester,
  ) async {
    // A dirty diaper logged without a size was logged that way on purpose.
    // Defaulting here would save a measurement nobody took.
    await openSheet(
      tester,
      existing: DiaperEvent(
        id: 'd1',
        type: DiaperType.dirty,
        time: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );

    expect(selectedSize(tester), isNull);
  });
}
