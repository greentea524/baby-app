import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/features/growth/growth_log_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens the growth sheet with [unitSystem] persisted, so the fields are
/// built the way they would be for a caregiver with that setting.
Future<void> _openSheet(WidgetTester tester, String unitSystem) async {
  SharedPreferences.setMockInitialValues({'unit_system': unitSystem});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGrowthLog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('metric offers one kilogram field and centimetres', (
    tester,
  ) async {
    await _openSheet(tester, 'metric');

    expect(find.text('Weight'), findsOneWidget);
    // The pounds/ounces pair collapses to a single field.
    expect(find.text('Ounces'), findsNothing);
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('lb'), findsNothing);
    // Height and head circumference.
    expect(find.text('cm'), findsNWidgets(2));
    expect(find.text('in'), findsNothing);
  });

  testWidgets('US splits weight into pounds and ounces, with inches', (
    tester,
  ) async {
    await _openSheet(tester, 'us');

    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Ounces'), findsOneWidget);
    expect(find.text('lb'), findsOneWidget);
    expect(find.text('oz'), findsOneWidget);
    expect(find.text('in'), findsNWidgets(2));
    expect(find.text('kg'), findsNothing);
  });

  testWidgets('an unset preference falls back to US', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGrowthLog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Ounces'), findsOneWidget);
    expect(find.text('lb'), findsOneWidget);
  });

  // Separate tests rather than a loop: reopening the sheet in one tester
  // leaves the first modal route in the navigator, so the finders match twice.
  testWidgets('metric keeps all three measurements', (tester) async {
    await _openSheet(tester, 'metric');
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Height'), findsOneWidget);
    expect(find.text('Head circumference'), findsOneWidget);
  });

  testWidgets('US keeps all three measurements', (tester) async {
    await _openSheet(tester, 'us');
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Height'), findsOneWidget);
    expect(find.text('Head circumference'), findsOneWidget);
  });
}
