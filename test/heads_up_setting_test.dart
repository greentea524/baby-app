import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';
import 'package:baby_app/features/reminders/reminder_providers.dart';

/// How much notice the Home chip gives before a feed is due, and that the
/// number the caregiver picks is the one the chip actually uses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the stored setting', () {
    test('defaults to a quarter hour', () async {
      final container = await containerWith({});
      final settings = container.read(reminderSettingsProvider);
      expect(settings.headsUpMinutes, defaultHeadsUpMinutes);
      expect(settings.headsUp, const Duration(minutes: 15));
    });

    test('is read back from preferences', () async {
      final container = await containerWith({'reminder_heads_up_minutes': 30});
      expect(
        container.read(reminderSettingsProvider).headsUp,
        const Duration(minutes: 30),
      );
    });

    test('survives a round trip through the notifier', () async {
      final container = await containerWith({});
      await container
          .read(reminderSettingsProvider.notifier)
          .setHeadsUpMinutes(45);

      expect(container.read(reminderSettingsProvider).headsUpMinutes, 45);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('reminder_heads_up_minutes'), 45);
    });

    test('does not disturb the mode or the interval', () async {
      final container = await containerWith({'reminder_interval_minutes': 240});
      await container
          .read(reminderSettingsProvider.notifier)
          .setHeadsUpMinutes(10);

      final settings = container.read(reminderSettingsProvider);
      expect(settings.intervalMinutes, 240);
      expect(settings.mode, ReminderMode.fixedInterval);
    });

    test('every offered option is a real choice', () async {
      expect(headsUpOptions, contains(0));
      expect(headsUpOptions, contains(defaultHeadsUpMinutes));
      expect(
        headsUpOptions.toSet(),
        hasLength(headsUpOptions.length),
        reason: 'a duplicate would break the dropdown',
      );
      expect(
        headsUpOptions,
        orderedEquals([...headsUpOptions]..sort()),
        reason: 'the menu should read in order',
      );
    });
  });

  group('what the chip does with it', () {
    final due = DateTime(2026, 8, 5, 14, 0);
    FeedDueState stateAt(Duration before, int headsUpMinutes) {
      final settings = ReminderSettings(
        mode: ReminderMode.fixedInterval,
        intervalMinutes: 180,
        headsUpMinutes: headsUpMinutes,
      );
      return feedDueState(
        due,
        now: due.subtract(before),
        within: settings.headsUp,
      );
    }

    test('a wider setting starts warning earlier', () {
      expect(stateAt(const Duration(minutes: 25), 15), FeedDueState.upcoming);
      expect(stateAt(const Duration(minutes: 25), 30), FeedDueState.soon);
    });

    test('off never goes amber, only red', () {
      // A due time is always strictly after now, so nothing lands inside a
      // zero-length window — the state skips straight from upcoming to
      // overdue.
      expect(stateAt(const Duration(minutes: 30), 0), FeedDueState.upcoming);
      expect(stateAt(const Duration(minutes: 1), 0), FeedDueState.upcoming);
      expect(stateAt(Duration.zero, 0), FeedDueState.overdue);
    });

    test('overdue outranks the setting, however wide', () {
      expect(stateAt(const Duration(minutes: -5), 60), FeedDueState.overdue);
    });

    test('an hour of notice still reads as upcoming beyond it', () {
      expect(stateAt(const Duration(minutes: 61), 60), FeedDueState.upcoming);
      expect(stateAt(const Duration(minutes: 60), 60), FeedDueState.soon);
    });
  });
}
