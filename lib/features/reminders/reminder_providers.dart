import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../data/repositories/repository_providers.dart';
import 'feed_prediction.dart';

/// How the "next feed" reminder is derived (KAN-133).
enum ReminderMode {
  /// No reminder shown.
  off('Off'),

  /// Rolling average of recent feed intervals (KAN-154).
  predictive('Predicted'),

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
    return ReminderSettings(
      mode:
          ReminderMode.values.asNameMap()[prefs.getString(_modeKey)] ??
          ReminderMode.predictive,
      intervalMinutes:
          prefs.getInt(_intervalKey) ?? defaultReminderIntervalMinutes,
    );
  }

  Future<void> setMode(ReminderMode mode) async {
    state = state.copyWith(mode: mode);
    await ref.read(sharedPreferencesProvider).setString(_modeKey, mode.name);
  }

  Future<void> setIntervalMinutes(int minutes) async {
    state = state.copyWith(intervalMinutes: minutes);
    await ref.read(sharedPreferencesProvider).setInt(_intervalKey, minutes);
  }
}

/// The prediction backing the home reminder card, honouring the chosen mode.
final feedPredictionProvider = Provider<FeedPrediction>((ref) {
  final settings = ref.watch(reminderSettingsProvider);
  if (settings.mode == ReminderMode.off) return FeedPrediction.none;

  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  if (feeds.isEmpty) return FeedPrediction.none;

  if (settings.mode == ReminderMode.fixedInterval) {
    final due = fixedIntervalDue(feeds, settings.intervalMinutes);
    return FeedPrediction(
      nextDue: due,
      averageIntervalMinutes: settings.intervalMinutes,
      intervalSamples: 0,
      lastFeedAt: due?.subtract(Duration(minutes: settings.intervalMinutes)),
    );
  }
  return predictNextFeed(feeds);
});
