import 'package:cloud_firestore/cloud_firestore.dart';

/// A caregiver's push-notification preferences, stored at
/// `notificationPrefs/{uid}` (KAN-167).
///
/// The scheduled reminder function reads these server-side, so times are kept
/// as **minutes from local midnight** plus the caregiver's UTC offset — the
/// function has no other way to know what "10 PM" means for this person.
class NotificationPrefs {
  const NotificationPrefs({
    this.enabled = true,
    this.quietHoursEnabled = false,
    this.quietStartMinutes = defaultQuietStart,
    this.quietEndMinutes = defaultQuietEnd,
    this.timezoneOffsetMinutes = 0,
    this.overdueThresholdMinutes = 0,
    this.reminderIntervalMinutes = defaultReminderInterval,
    this.remindersOff = false,
  });

  static const defaultQuietStart = 22 * 60; // 10:00 PM
  static const defaultQuietEnd = 7 * 60; // 7:00 AM
  static const defaultReminderInterval = 180; // 3 hours

  /// Master switch for background reminders on the server side. Distinct from
  /// the per-device push opt-in, which only controls token registration.
  final bool enabled;

  final bool quietHoursEnabled;

  /// Minutes from local midnight. The window may wrap midnight, which is the
  /// normal case (22:00 → 07:00).
  final int quietStartMinutes;
  final int quietEndMinutes;

  /// The caregiver's offset from UTC, captured when they last saved. Lets the
  /// server resolve their local wall-clock time.
  final int timezoneOffsetMinutes;

  /// Extra grace past the due time before notifying. 0 keeps the original
  /// behaviour of alerting as soon as a feed is overdue.
  final int overdueThresholdMinutes;

  /// The caregiver's chosen gap between feeds, mirrored from the local
  /// setting so the server can work out when a feed is overdue.
  ///
  /// The reminder used to be derived server-side from a rolling average, which
  /// needed nothing published; a caregiver-set interval has to be.
  final int reminderIntervalMinutes;

  /// The caregiver turned the reminder off in the app. Distinct from
  /// [enabled], which is the master switch for background push.
  final bool remindersOff;

  NotificationPrefs copyWith({
    bool? enabled,
    bool? quietHoursEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
    int? timezoneOffsetMinutes,
    int? overdueThresholdMinutes,
    int? reminderIntervalMinutes,
    bool? remindersOff,
  }) => NotificationPrefs(
    enabled: enabled ?? this.enabled,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
    quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    timezoneOffsetMinutes: timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
    overdueThresholdMinutes:
        overdueThresholdMinutes ?? this.overdueThresholdMinutes,
    reminderIntervalMinutes:
        reminderIntervalMinutes ?? this.reminderIntervalMinutes,
    remindersOff: remindersOff ?? this.remindersOff,
  );

  factory NotificationPrefs.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const NotificationPrefs();
    return NotificationPrefs(
      enabled: data['enabled'] as bool? ?? true,
      quietHoursEnabled: data['quietHoursEnabled'] as bool? ?? false,
      quietStartMinutes:
          (data['quietStartMinutes'] as num?)?.toInt() ?? defaultQuietStart,
      quietEndMinutes:
          (data['quietEndMinutes'] as num?)?.toInt() ?? defaultQuietEnd,
      timezoneOffsetMinutes:
          (data['timezoneOffsetMinutes'] as num?)?.toInt() ?? 0,
      overdueThresholdMinutes:
          (data['overdueThresholdMinutes'] as num?)?.toInt() ?? 0,
      // Absent for anyone who last saved before the interval was published;
      // the 3-hour default matches what the app defaults to.
      reminderIntervalMinutes:
          (data['reminderIntervalMinutes'] as num?)?.toInt() ??
          defaultReminderInterval,
      remindersOff: data['remindersOff'] as bool? ?? false,
    );
  }

  factory NotificationPrefs.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => NotificationPrefs.fromMap(doc.data());

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'quietHoursEnabled': quietHoursEnabled,
    'quietStartMinutes': quietStartMinutes,
    'quietEndMinutes': quietEndMinutes,
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
    'overdueThresholdMinutes': overdueThresholdMinutes,
    'reminderIntervalMinutes': reminderIntervalMinutes,
    'remindersOff': remindersOff,
  };

  /// Whether [localMinutes] (minutes from local midnight) falls inside the
  /// quiet window. Handles windows that wrap past midnight.
  ///
  /// Mirrored server-side in `functions/src/index.ts` — keep the two in step.
  bool isQuietAt(int localMinutes) {
    if (!quietHoursEnabled) return false;
    if (quietStartMinutes == quietEndMinutes) return false;
    if (quietStartMinutes < quietEndMinutes) {
      return localMinutes >= quietStartMinutes &&
          localMinutes < quietEndMinutes;
    }
    // Wraps midnight: quiet from start until end the next morning.
    return localMinutes >= quietStartMinutes || localMinutes < quietEndMinutes;
  }

  /// "10:00 PM" for minutes-from-midnight, for labels and summaries.
  static String formatMinutes(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final period = h24 < 12 ? 'AM' : 'PM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }

  /// "10:00 PM – 7:00 AM" for the settings summary line.
  String get quietWindowLabel =>
      '${formatMinutes(quietStartMinutes)} – ${formatMinutes(quietEndMinutes)}';
}
