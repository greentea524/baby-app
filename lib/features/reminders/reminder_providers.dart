import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/notification_prefs.dart';
import '../../data/repositories/repository_providers.dart';
import 'feed_prediction.dart';

/// How the "next feed" reminder is derived (KAN-133).
///
/// The rolling-average "Predicted" mode was removed. A single statistic can't
/// describe a rhythm that runs 3-hourly by day and 6-hourly at night: on an
/// otherwise clean log it reminded ~26 minutes late all day, then fired hours
/// early the first time the baby slept through. The average survives as an
/// informational figure (`feedRhythm`) that tells a caregiver what interval to
/// set — it no longer sets it for them.
enum ReminderMode {
  /// No reminder shown.
  off('Off'),

  /// A user-set fixed gap since the last feed (KAN-155).
  fixedInterval('Fixed');

  const ReminderMode(this.label);

  final String label;
}

const _modeKey = 'reminder_mode';
const _intervalKey = 'reminder_interval_minutes';
const _headsUpKey = 'reminder_heads_up_minutes';

/// What this device last confirmed the account's copy holds.
///
/// Not the same as the chosen value: a change that never reached Firestore
/// leaves these two apart, which is exactly how [adoptedSetting] tells an
/// unpushed local change from a change made on another device (#27).
const _intervalSyncedKey = 'reminder_interval_synced';
const _offSyncedKey = 'reminder_off_synced';

const defaultReminderIntervalMinutes = 180; // 3 hours

/// Which value wins when this device's setting and the account's disagree —
/// the value to adopt, or null to keep the device's own.
///
/// The interval is stored twice: locally, which is what the in-app card reads,
/// and on the account, which is what the reminder Cloud Function reads. Only
/// the local copy was ever read back, so a second device kept showing its own
/// stale interval — or the 3-hour default, on a device that had never set one
/// — while push reminders used the account's (#27).
///
/// Neither copy carries a timestamp, so "newest wins" is not available. What
/// is available is whether this device is carrying a change that never landed:
///
/// | chosen | lastSynced | server | outcome           |
/// |--------|-----------|--------|-------------------|
/// | unset  | —         | 240    | adopt 240         |
/// | 240    | 240       | 300    | adopt 300         |
/// | 240    | 240       | 240    | keep — they agree |
/// | 240    | unset/180 | 180    | keep 240, resync  |
///
/// A device that has chosen something the account has not acknowledged is the
/// one holding the newer value, so it wins and pushes again. Otherwise the
/// account wins, because any difference came from somewhere else.
T? adoptedSetting<T>({
  required T? chosen,
  required T? lastSynced,
  required T server,
}) {
  if (chosen != null && chosen != lastSynced) return null;
  if (server == chosen) return null;
  return server;
}

/// The choices offered for [ReminderSettings.headsUpMinutes]. 0 is off.
const headsUpOptions = <int>[0, 10, 15, 20, 30, 45, 60];

class ReminderSettings {
  const ReminderSettings({
    required this.mode,
    required this.intervalMinutes,
    this.headsUpMinutes = defaultHeadsUpMinutes,
  });

  final ReminderMode mode;
  final int intervalMinutes;

  /// How long before a feed is due that the Home chip turns amber. 0 turns
  /// the warning off, leaving the chip to go straight from neutral to red.
  ///
  /// How much notice is useful depends on what it is for — reaching a chair
  /// is a minute, thawing a bag of milk is closer to an hour — so this is the
  /// caregiver's to set rather than a number chosen for them.
  final int headsUpMinutes;

  /// The window [feedDueState] takes. 0 means no amber at all: a due time is
  /// always strictly after now, so nothing falls inside a zero-length window.
  Duration get headsUp => Duration(minutes: headsUpMinutes);

  ReminderSettings copyWith({
    ReminderMode? mode,
    int? intervalMinutes,
    int? headsUpMinutes,
  }) => ReminderSettings(
    mode: mode ?? this.mode,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    headsUpMinutes: headsUpMinutes ?? this.headsUpMinutes,
  );
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
      ReminderSettingsNotifier.new,
    );

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  @override
  ReminderSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);

    // Local preferences stay the immediate answer — there is no loading state
    // to sit through and the setting has to work offline. The account's copy
    // arrives later and is reconciled in [_reconcile] (#27).
    ref.listen(notificationPrefsProvider, (_, next) {
      final remote = next.value;
      if (remote != null) _reconcile(remote);
    }, fireImmediately: true);

    // Anyone still carrying the removed 'predictive' value no longer resolves
    // and lands on the default — which is the intended migration: their
    // reminder becomes a fixed interval at the stored (or default) gap.
    return ReminderSettings(
      mode:
          ReminderMode.values.asNameMap()[prefs.getString(_modeKey)] ??
          ReminderMode.fixedInterval,
      intervalMinutes:
          prefs.getInt(_intervalKey) ?? defaultReminderIntervalMinutes,
      headsUpMinutes: prefs.getInt(_headsUpKey) ?? defaultHeadsUpMinutes,
    );
  }

  /// Whether the reminder is switched off according to this device's stored
  /// preference, or null if it has never chosen.
  ///
  /// The removed 'predictive' value resolves to nothing and so reads as "not
  /// off", matching the migration in [build].
  static bool? _storedOff(SharedPreferences prefs) {
    final name = prefs.getString(_modeKey);
    if (name == null) return null;
    return ReminderMode.values.asNameMap()[name] == ReminderMode.off;
  }

  /// Takes the account's interval and on/off state when they are the newer
  /// ones, and pushes this device's again when they are not.
  Future<void> _reconcile(NotificationPrefs remote) async {
    // Signed out, the stream is emitting defaults rather than the account's
    // values. Adopting those would read as the account asking for a 3-hour
    // interval every time someone signs out.
    if (!ref.read(hasAccountPrefsProvider)) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final storedOff = _storedOff(prefs);
    final storedInterval = prefs.getInt(_intervalKey);
    final syncedOff = prefs.getBool(_offSyncedKey);
    final syncedInterval = prefs.getInt(_intervalSyncedKey);

    final interval = adoptedSetting(
      chosen: storedInterval,
      lastSynced: syncedInterval,
      server: remote.reminderIntervalMinutes,
    );
    final off = adoptedSetting(
      chosen: storedOff,
      lastSynced: syncedOff,
      server: remote.remindersOff,
    );

    if (interval == null && off == null) {
      // Nothing to take. If this device is holding a change the account never
      // acknowledged, this is the moment to try pushing it again — otherwise
      // a sync that failed once would stay failed until the setting was next
      // touched by hand.
      final unpushed =
          (storedInterval != null && storedInterval != syncedInterval) ||
          (storedOff != null && storedOff != syncedOff);
      if (unpushed) await _syncToServer();
      return;
    }

    final mode = off == null
        ? null
        : (off ? ReminderMode.off : ReminderMode.fixedInterval);
    state = state.copyWith(mode: mode, intervalMinutes: interval);

    // Written straight back, both as the chosen value and as the acknowledged
    // one: this device now agrees with the account and has nothing to push.
    if (interval != null) {
      await prefs.setInt(_intervalKey, interval);
      await prefs.setInt(_intervalSyncedKey, interval);
    }
    if (mode != null) {
      await prefs.setString(_modeKey, mode.name);
      await prefs.setBool(_offSyncedKey, off!);
    }
  }

  Future<void> setMode(ReminderMode mode) async {
    state = state.copyWith(mode: mode);
    await ref.read(sharedPreferencesProvider).setString(_modeKey, mode.name);
    await _syncToServer();
  }

  Future<void> setIntervalMinutes(int minutes) async {
    state = state.copyWith(intervalMinutes: minutes);
    await ref.read(sharedPreferencesProvider).setInt(_intervalKey, minutes);
    await _syncToServer();
  }

  /// Deliberately not synced to Firestore, unlike the mode and interval. The
  /// heads-up only tints a chip on this device's Home screen — the Cloud
  /// Function has no chip to tint, and pushing early would turn a visual cue
  /// into a second notification nobody asked for.
  Future<void> setHeadsUpMinutes(int minutes) async {
    state = state.copyWith(headsUpMinutes: minutes);
    await ref.read(sharedPreferencesProvider).setInt(_headsUpKey, minutes);
  }

  /// Mirrors the interval into Firestore so the reminder Cloud Function can
  /// use it. The server used to derive its own due time from the rolling
  /// average; with a caregiver-set interval it has no way to know the gap
  /// unless we publish it.
  ///
  /// Best-effort, and now actually so: the failure used to escape as an
  /// unhandled async error, since neither this method nor the settings screen
  /// caught it. The local setting is what the in-app card reads, so a failed
  /// sync leaves the caregiver's choice standing and the unacknowledged marker
  /// behind for [_reconcile] to retry from.
  Future<void> _syncToServer() async {
    final repo = ref.read(notificationPrefsRepositoryProvider);
    if (repo == null) return;
    final interval = state.intervalMinutes;
    final off = state.mode == ReminderMode.off;
    try {
      await repo.saveReminderCadence(
        intervalMinutes: interval,
        remindersOff: off,
      );
    } catch (_) {
      return;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_intervalSyncedKey, interval);
    await prefs.setBool(_offSyncedKey, off);
  }
}

/// When the next feed is due, or null when reminders are off or nothing has
/// been logged. A fixed gap since the last full feed — see [ReminderMode].
final nextFeedDueProvider = Provider<DateTime?>((ref) {
  final settings = ref.watch(reminderSettingsProvider);
  if (settings.mode == ReminderMode.off) return null;

  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  if (feeds.isEmpty) return null;

  return fixedIntervalDue(feeds, settings.intervalMinutes);
});

/// How often the baby has actually been feeding lately. Informational — it
/// helps a caregiver choose their interval, and never sets it.
final feedRhythmProvider = Provider<FeedRhythm>((ref) {
  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  return feedRhythm(feeds);
});
