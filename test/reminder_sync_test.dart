import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/data/models/notification_prefs.dart';
import 'package:baby_app/data/repositories/repository_providers.dart';
import 'package:baby_app/features/reminders/reminder_providers.dart';

/// The feed interval reaching a second device (#27).
///
/// The setting lives in two places with different scopes: local preferences,
/// which the in-app card reads, and the account document, which the reminder
/// Cloud Function reads. Only the local copy was ever read back, so a device
/// that had never set an interval showed the 3-hour default while push
/// reminders ran at whatever the account said.
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
    container.listen(reminderSettingsProvider, (_, _) {});
    return (container, account);
  }

  /// Pushes one set of account values through and lets the notifier settle.
  Future<void> accountSays(
    StreamController<NotificationPrefs> account,
    ProviderContainer container, {
    int? interval,
    bool remindersOff = false,
  }) async {
    account.add(
      NotificationPrefs(
        reminderIntervalMinutes: interval ?? defaultReminderIntervalMinutes,
        remindersOff: remindersOff,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  group('which copy wins', () {
    test('a device that has never chosen takes the account\'s interval', () {
      expect(
        adoptedSetting(chosen: null, lastSynced: null, server: 240),
        240,
      );
    });

    test('a change made on another device is adopted', () {
      expect(adoptedSetting(chosen: 240, lastSynced: 240, server: 300), 300);
    });

    test('nothing happens when the two already agree', () {
      expect(adoptedSetting(chosen: 240, lastSynced: 240, server: 240), isNull);
    });

    test('a local change the account never acknowledged is kept', () {
      // The whole reason lastSynced exists. Without it this case is
      // indistinguishable from the account holding the newer value, and the
      // caregiver's offline edit gets thrown away.
      expect(adoptedSetting(chosen: 300, lastSynced: 240, server: 240), isNull);
      expect(adoptedSetting(chosen: 240, lastSynced: null, server: 180), isNull);
    });

    test('works for the on/off flag too, false being a real answer', () {
      // `false` must not be confused with "unset" — a caregiver who has left
      // reminders on has chosen something.
      expect(
        adoptedSetting(chosen: false, lastSynced: false, server: true),
        isTrue,
      );
      expect(
        adoptedSetting(chosen: false, lastSynced: null, server: true),
        isNull,
      );
    });
  });

  group('a device that has never set an interval', () {
    test("takes the account's", () async {
      final (container, account) = await harness();
      expect(
        container.read(reminderSettingsProvider).intervalMinutes,
        defaultReminderIntervalMinutes,
      );

      await accountSays(account, container, interval: 240);

      expect(container.read(reminderSettingsProvider).intervalMinutes, 240);
    });

    test('remembers it, so the next launch starts there', () async {
      final (container, account) = await harness();
      await accountSays(account, container, interval: 240);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('reminder_interval_minutes'), 240);
      // And marked as acknowledged, so it is not mistaken for a local change
      // waiting to be pushed.
      expect(prefs.getInt('reminder_interval_synced'), 240);
    });

    test('takes reminders being switched off as well', () async {
      final (container, account) = await harness();
      await accountSays(account, container, remindersOff: true);

      expect(container.read(reminderSettingsProvider).mode, ReminderMode.off);
    });
  });

  group('a device that has set one', () {
    test('follows a change made on another device', () async {
      final (container, account) = await harness(
        stored: {
          'reminder_interval_minutes': 240,
          'reminder_interval_synced': 240,
        },
      );
      await accountSays(account, container, interval: 300);

      expect(container.read(reminderSettingsProvider).intervalMinutes, 300);
    });

    test('keeps a change the account never acknowledged', () async {
      // Set offline: local moved to 300, the account still says 240.
      final (container, account) = await harness(
        stored: {
          'reminder_interval_minutes': 300,
          'reminder_interval_synced': 240,
        },
      );
      await accountSays(account, container, interval: 240);

      expect(container.read(reminderSettingsProvider).intervalMinutes, 300);
    });

    test('is left alone when the account agrees', () async {
      final (container, account) = await harness(
        stored: {
          'reminder_interval_minutes': 240,
          'reminder_interval_synced': 240,
        },
      );
      await accountSays(account, container, interval: 240);

      expect(container.read(reminderSettingsProvider).intervalMinutes, 240);
    });
  });

  test('signing out does not reset the interval to the default', () async {
    // Signed out the stream carries defaults, which are not the account
    // speaking. Adopting them would quietly undo the caregiver's choice.
    final (container, account) = await harness(
      stored: {
        'reminder_interval_minutes': 240,
        'reminder_interval_synced': 240,
      },
      signedIn: false,
    );
    await accountSays(account, container);

    expect(container.read(reminderSettingsProvider).intervalMinutes, 240);
  });

  test('the heads-up is never taken from the account', () async {
    // Deliberately device-local: it only tints a chip on this device's Home
    // screen, and there is nothing on the account to take it from.
    final (container, account) = await harness(
      stored: {'reminder_heads_up_minutes': 45},
    );
    await accountSays(account, container, interval: 240);

    expect(container.read(reminderSettingsProvider).headsUpMinutes, 45);
  });
}
