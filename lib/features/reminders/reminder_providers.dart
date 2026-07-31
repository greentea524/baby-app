import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
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
const defaultReminderIntervalMinutes = 180; // 3 hours

class ReminderSettings {
  const ReminderSettings({required this.mode, required this.intervalMinutes});

  final ReminderMode mode;
  final int intervalMinutes;

  ReminderSettings copyWith({ReminderMode? mode, int? intervalMinutes}) =>
      ReminderSettings(
        mode: mode ?? this.mode,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
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
    // Anyone still carrying the removed 'predictive' value no longer resolves
    // and lands on the default — which is the intended migration: their
    // reminder becomes a fixed interval at the stored (or default) gap.
    return ReminderSettings(
      mode:
          ReminderMode.values.asNameMap()[prefs.getString(_modeKey)] ??
          ReminderMode.fixedInterval,
      intervalMinutes:
          prefs.getInt(_intervalKey) ?? defaultReminderIntervalMinutes,
    );
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

  /// Mirrors the interval into Firestore so the reminder Cloud Function can
  /// use it. The server used to derive its own due time from the rolling
  /// average; with a caregiver-set interval it has no way to know the gap
  /// unless we publish it.
  ///
  /// Best-effort: the local setting is what the in-app card reads, so a failed
  /// sync degrades to push reminders using the last synced interval rather
  /// than breaking the setting.
  Future<void> _syncToServer() async {
    final repo = ref.read(notificationPrefsRepositoryProvider);
    if (repo == null) return;
    await repo.saveReminderCadence(
      intervalMinutes: state.intervalMinutes,
      remindersOff: state.mode == ReminderMode.off,
    );
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
