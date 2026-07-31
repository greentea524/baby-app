import 'package:baby_app/data/models/notification_prefs.dart';
import 'package:baby_app/features/reminders/reminder_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quiet hours', () {
    const overnight = NotificationPrefs(
      quietHoursEnabled: true,
      quietStartMinutes: 22 * 60, // 10 PM
      quietEndMinutes: 7 * 60, // 7 AM
    );

    test('a window that wraps midnight covers both sides of it', () {
      expect(overnight.isQuietAt(23 * 60), isTrue); // 11 PM
      expect(overnight.isQuietAt(2 * 60), isTrue); // 2 AM
      expect(overnight.isQuietAt(22 * 60), isTrue); // exactly 10 PM
    });

    test('daytime falls outside an overnight window', () {
      expect(overnight.isQuietAt(7 * 60), isFalse); // 7 AM, window ended
      expect(overnight.isQuietAt(12 * 60), isFalse);
      expect(overnight.isQuietAt(21 * 60 + 59), isFalse);
    });

    test('a same-day window does not wrap', () {
      const nap = NotificationPrefs(
        quietHoursEnabled: true,
        quietStartMinutes: 13 * 60,
        quietEndMinutes: 15 * 60,
      );
      expect(nap.isQuietAt(14 * 60), isTrue);
      expect(nap.isQuietAt(12 * 60), isFalse);
      expect(nap.isQuietAt(15 * 60), isFalse); // end is exclusive
      expect(nap.isQuietAt(23 * 60), isFalse);
    });

    test('nothing is quiet when the feature is off', () {
      const off = NotificationPrefs(
        quietStartMinutes: 22 * 60,
        quietEndMinutes: 7 * 60,
      );
      expect(off.isQuietAt(2 * 60), isFalse);
    });

    test('an empty window silences nothing', () {
      const degenerate = NotificationPrefs(
        quietHoursEnabled: true,
        quietStartMinutes: 8 * 60,
        quietEndMinutes: 8 * 60,
      );
      expect(degenerate.isQuietAt(8 * 60), isFalse);
    });
  });

  group('serialization', () {
    test('round-trips through a map', () {
      const prefs = NotificationPrefs(
        enabled: false,
        quietHoursEnabled: true,
        quietStartMinutes: 1290,
        quietEndMinutes: 400,
        timezoneOffsetMinutes: -420,
        overdueThresholdMinutes: 15,
      );
      final restored = NotificationPrefs.fromMap(prefs.toMap());
      expect(restored.enabled, isFalse);
      expect(restored.quietHoursEnabled, isTrue);
      expect(restored.quietStartMinutes, 1290);
      expect(restored.quietEndMinutes, 400);
      expect(restored.timezoneOffsetMinutes, -420);
      expect(restored.overdueThresholdMinutes, 15);
    });

    test('a missing document yields usable defaults', () {
      final prefs = NotificationPrefs.fromMap(null);
      expect(prefs.enabled, isTrue);
      expect(prefs.quietHoursEnabled, isFalse);
      expect(prefs.quietStartMinutes, NotificationPrefs.defaultQuietStart);
    });

    test('partial data falls back field by field', () {
      final prefs = NotificationPrefs.fromMap({'quietHoursEnabled': true});
      expect(prefs.quietHoursEnabled, isTrue);
      expect(prefs.enabled, isTrue);
      expect(prefs.quietEndMinutes, NotificationPrefs.defaultQuietEnd);
    });
  });

  group('formatting', () {
    test('renders 12-hour times with midnight and noon as 12', () {
      expect(NotificationPrefs.formatMinutes(0), '12:00 AM');
      expect(NotificationPrefs.formatMinutes(12 * 60), '12:00 PM');
      expect(NotificationPrefs.formatMinutes(22 * 60), '10:00 PM');
      expect(NotificationPrefs.formatMinutes(7 * 60 + 5), '7:05 AM');
    });

    test('summarises the window for the settings line', () {
      const prefs = NotificationPrefs(
        quietHoursEnabled: true,
        quietStartMinutes: 22 * 60,
        quietEndMinutes: 7 * 60,
      );
      expect(prefs.quietWindowLabel, '10:00 PM – 7:00 AM');
    });
  });

  group('reminder interval (published for the server)', () {
    test('round-trips through the map', () {
      const prefs = NotificationPrefs(
        reminderIntervalMinutes: 240,
        remindersOff: true,
      );
      final restored = NotificationPrefs.fromMap(prefs.toMap());
      expect(restored.reminderIntervalMinutes, 240);
      expect(restored.remindersOff, isTrue);
    });

    test('is published so the Cloud Function can read it', () {
      // The server has no other source for the caregiver's chosen gap.
      const prefs = NotificationPrefs(reminderIntervalMinutes: 150);
      expect(prefs.toMap()['reminderIntervalMinutes'], 150);
      expect(prefs.toMap()['remindersOff'], isFalse);
    });

    test('defaults for anyone who saved before the field existed', () {
      final prefs = NotificationPrefs.fromMap({'enabled': true});
      expect(
        prefs.reminderIntervalMinutes,
        NotificationPrefs.defaultReminderInterval,
      );
      expect(prefs.remindersOff, isFalse);
    });

    test('the default matches what the app defaults to', () {
      // A mismatch would mean push reminders on a different cadence to the
      // in-app card until the caregiver next touched the setting.
      expect(
        NotificationPrefs.defaultReminderInterval,
        defaultReminderIntervalMinutes,
      );
    });
  });
}
