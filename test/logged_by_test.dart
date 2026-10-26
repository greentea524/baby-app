import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/auth/auth_providers.dart';
import 'package:baby_app/core/device/logged_by.dart';
import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/activity_entry.dart';
import 'package:baby_app/data/models/diaper_event.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/activity/activity_tile.dart';
import 'package:baby_app/features/settings/settings_screen.dart';

/// Who logged an entry, when one account is shared across devices: each
/// device can be given a name, and what it logs says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('who logged it', () {
    String? who(String? byName) => whoLogged(byName: byName, myName: 'Mom');

    test('is "you" for what this device logged', () {
      expect(who('Mom'), 'you');
    });

    test('and the other device\'s name, on the same account', () {
      expect(who('iPad'), 'iPad');
      expect(who('Dad'), 'Dad');
    });

    test('is nothing for an entry from before names', () {
      // Not "you" from its account: on a shared account that would be
      // every entry, from every device.
      expect(who(null), isNull);
      expect(who('  '), isNull);
    });
  });

  Future<ProviderContainer> container(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final stored = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(stored),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('the device\'s name', () {
    test('is kept on the device, trimmed, and blank clears it', () async {
      final c = await container({});
      expect(c.read(deviceNameProvider), isNull);

      await c.read(deviceNameProvider.notifier).set('  iPad ');
      expect(c.read(deviceNameProvider), 'iPad');
      expect(c.read(loggedByProvider), 'iPad');
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString('device_name'), 'iPad');

      await c.read(deviceNameProvider.notifier).set('');
      expect(c.read(deviceNameProvider), isNull);
      expect(prefs.getString('device_name'), isNull);
    });

    test('is read back when the app starts again', () async {
      final c = await container({'device_name': 'Dad'});
      expect(c.read(loggedByProvider), 'Dad');
    });

    test('is cut to its limit', () async {
      final c = await container({});
      await c.read(deviceNameProvider.notifier).set('x' * 50);
      expect(c.read(deviceNameProvider), hasLength(deviceNameMax));
    });
  });

  group('in the activity log', () {
    Future<void> pumpTile(
      WidgetTester tester,
      ActivityEntry entry, {
      String? deviceName,
    }) async {
      SharedPreferences.setMockInitialValues({
        'unit_system': 'metric',
        'device_name': ?deviceName,
      });
      final stored = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(stored),
            authStateProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ActivityTile(entry: entry, now: DateTime(2026, 10, 26, 15)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final at = DateTime(2026, 10, 26, 13);

    testWidgets('a feed says which device it came from', (tester) async {
      await pumpTile(
        tester,
        FeedingEntry(
          FeedingEvent(
            id: 'f',
            type: FeedingType.bottle,
            startTime: at,
            amountMl: 120,
            byName: 'iPad',
          ),
        ),
        deviceName: 'Mom',
      );
      expect(find.textContaining('by iPad'), findsOneWidget);
    });

    testWidgets('and "you" on the device that logged it', (tester) async {
      await pumpTile(
        tester,
        DiaperEntry(
          DiaperEvent(id: 'd', type: DiaperType.wet, time: at, byName: 'Mom'),
        ),
        deviceName: 'Mom',
      );
      expect(find.text('by you'), findsOneWidget);
    });

    testWidgets('a pump too', (tester) async {
      await pumpTile(
        tester,
        PumpingEntry(
          PumpingEvent(id: 'p', time: at, amountMl: 90, byName: 'Dad'),
        ),
        deviceName: 'iPad',
      );
      expect(find.textContaining('by Dad'), findsOneWidget);
    });

    testWidgets('and nothing for an entry from before names', (tester) async {
      await pumpTile(
        tester,
        DiaperEntry(DiaperEvent(id: 'd', type: DiaperType.wet, time: at)),
      );
      expect(find.textContaining('by '), findsNothing);
    });
  });

  testWidgets('is set in Settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final stored = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(stored),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Name on this device'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'iPad');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(c.read(deviceNameProvider), 'iPad');
    expect(find.text('Logs from here say "by iPad"'), findsOneWidget);
  });
}
