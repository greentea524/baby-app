import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/notification_prefs.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/pumping/pump_schedule.dart';

/// The pumping cadence reaching a second device.
///
/// Same three-way merge the feed interval runs (#27), and for the same
/// reason: a caregiver who sets their cadence on a phone means it on the
/// tablet too. What differs is why it is published at all — nothing
/// server-side reads this one, so the account copy exists purely so the
/// caregiver's other devices can find it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A container with the account's stored preferences under test control.
  ///
  /// [signedIn] false makes [notificationPrefsProvider] mean what it means
  /// when nobody is signed in: defaults, standing in for nothing.
  Future<(ProviderContainer, StreamController<NotificationPrefs>)> harness({
    Map<String, Object> stored = const {},
    bool signedIn = true,
  }) async {
    SharedPreferences.setMockInitialValues(Map.of(stored));
    final prefs = await SharedPreferences.getInstance();
    final account = StreamController<NotificationPrefs>.broadcast();
    addTearDown(account.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        hasAccountPrefsProvider.overrideWithValue(signedIn),
        notificationPrefsProvider.overrideWith((ref) => account.stream),
      ],
    );
    addTearDown(container.dispose);
    // Providers auto-dispose, and a bare read builds the notifier only to
    // throw it away — taking its subscription to the account with it. In the
    // app a screen is always watching; here that has to be said out loud.
    container.listen(pumpIntervalProvider, (_, _) {});
    return (container, account);
  }

  /// Pushes one set of account values through and lets the notifier settle.
  Future<void> accountSays(
    StreamController<NotificationPrefs> account, {
    int pumpInterval = 0,
  }) async {
    account.add(NotificationPrefs(pumpIntervalMinutes: pumpInterval));
    await Future<void>.delayed(Duration.zero);
  }

  group('a device that has never set a cadence', () {
    test("takes the account's", () async {
      final (container, account) = await harness();
      expect(container.read(pumpIntervalProvider), 0);

      await accountSays(account, pumpInterval: 120);

      expect(container.read(pumpIntervalProvider), 120);
    });

    test('remembers it, so the next launch starts there', () async {
      final (container, account) = await harness();
      await accountSays(account, pumpInterval: 120);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('pump_interval_minutes'), 120);
      // And marked as acknowledged, so it is not mistaken for a local change
      // waiting to be pushed.
      expect(prefs.getInt('pump_interval_synced'), 120);
    });

    test('and stays off when the account has none either', () async {
      final (container, account) = await harness();
      await accountSays(account);

      expect(container.read(pumpIntervalProvider), 0);
    });
  });

  group('a device that has set one', () {
    test('follows a change made on another device', () async {
      final (container, account) = await harness(
        stored: {'pump_interval_minutes': 120, 'pump_interval_synced': 120},
      );
      await accountSays(account, pumpInterval: 180);

      expect(container.read(pumpIntervalProvider), 180);
    });

    test('keeps a change the account never acknowledged', () async {
      // Set offline: local moved to 180, the account still says 120.
      final (container, account) = await harness(
        stored: {'pump_interval_minutes': 180, 'pump_interval_synced': 120},
      );
      await accountSays(account, pumpInterval: 120);

      expect(container.read(pumpIntervalProvider), 180);
    });

    test('is left alone when the account agrees', () async {
      final (container, account) = await harness(
        stored: {'pump_interval_minutes': 120, 'pump_interval_synced': 120},
      );
      await accountSays(account, pumpInterval: 120);

      expect(container.read(pumpIntervalProvider), 120);
    });

    test('follows the countdown being switched off elsewhere', () async {
      // 0 is a real answer, not "unset". Turning it off on one device has to
      // reach the others, or the tablet goes on counting to a schedule its
      // owner has abandoned.
      final (container, account) = await harness(
        stored: {'pump_interval_minutes': 120, 'pump_interval_synced': 120},
      );
      await accountSays(account);

      expect(container.read(pumpIntervalProvider), 0);
    });
  });

  test('signing out does not switch the countdown off', () async {
    // Signed out the stream carries defaults, which are not the account
    // speaking. Adopting them would quietly undo the caregiver's choice.
    final (container, account) = await harness(
      stored: {'pump_interval_minutes': 120, 'pump_interval_synced': 120},
      signedIn: false,
    );
    await accountSays(account);

    expect(container.read(pumpIntervalProvider), 120);
  });

  test('an account value already in hand is picked up at build', () async {
    // Ordering, not merging. The account stream is shared, so by the time
    // this notifier first builds something else — the settings screen, the
    // reminder provider — has usually already resolved it, and the listener
    // fires inside build rather than after it. The adopted value has to
    // survive that, and the notifier has to survive assigning state there.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        hasAccountPrefsProvider.overrideWithValue(true),
        notificationPrefsProvider.overrideWith(
          (ref) =>
              Stream.value(const NotificationPrefs(pumpIntervalMinutes: 120)),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.listen(notificationPrefsProvider, (_, _) {});
    await container.read(notificationPrefsProvider.future);

    container.listen(pumpIntervalProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);

    expect(container.read(pumpIntervalProvider), 120);
  });

  test('the feed interval is not taken for the pump one', () async {
    // Two cadences in one document, and they are nothing to do with each
    // other: a 3-hour feed reminder must not set a 3-hour pumping schedule.
    final (container, account) = await harness();
    account.add(const NotificationPrefs(reminderIntervalMinutes: 180));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(pumpIntervalProvider), 0);
  });
}
