import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/home/baby_switcher.dart';
import 'package:baby_app/features/settings/settings_screen.dart';

/// How hard it is to start destroying data by accident.
///
/// The delete screens themselves cannot be completed without typing the
/// baby's name or the account's email, so a stray tap has never been able to
/// lose anything. What these pin is the step before that: where the door to
/// those screens is, and how easy it is to open one while looking for
/// something else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baby = Baby(
    id: 'baby1',
    name: 'Ada',
    birthDate: DateTime(2026, 2, 1),
    ownerUid: 'alice',
    members: const {'alice': CaregiverRole.owner},
  );

  Future<void> pump(WidgetTester tester, Widget home) async {
    SharedPreferences.setMockInitialValues({});
    final stored = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(stored),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          babiesStreamProvider.overrideWith((ref) => Stream.value([baby])),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the baby picker', () {
    Future<void> openPicker(WidgetTester tester) async {
      await pump(
        tester,
        const Scaffold(appBar: null, body: Center(child: BabySwitcher())),
      );
      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers no way to delete a baby', (tester) async {
      // The sheet is opened to switch baby, several times a day in a
      // two-child household. Add and Delete a thumb's width apart on a sheet
      // reached that often is the wrong place for the door to a delete.
      await openPicker(tester);

      expect(find.text('Add baby'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('but still opens the edit form', (tester) async {
      // Removing the menu must not take editing with it — that is the one
      // thing the menu was still worth having.
      await openPicker(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Edit baby'), findsOneWidget);
    });
  });

  group('the settings deletes', () {
    /// Settings is longer than a phone, so the section has to be scrolled to
    /// before it is built at all.
    Future<void> openSettings(WidgetTester tester) async {
      await pump(tester, const SettingsScreen());
      await tester.scrollUntilVisible(
        find.text('Delete data or account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('are folded away on arrival', (tester) async {
      // Not hidden — collapsed. They belong beside Export, which is the
      // other half of owning the data; what they do not need is to be
      // readable at a glance while someone hunts for the units setting.
      await openSettings(tester);

      expect(find.text('Delete data or account'), findsOneWidget);
      expect(find.text('Delete data'), findsNothing);
      expect(find.text('Delete account'), findsNothing);
    });

    testWidgets('and are both there once the section is opened', (
      tester,
    ) async {
      await openSettings(tester);
      await tester.tap(find.text('Delete data or account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete data'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
    });
  });
}
