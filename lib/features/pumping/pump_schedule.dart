import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs/adopted_setting.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/notification_prefs.dart';
import '../../data/repositories/repository_providers.dart';

/// How often the caregiver means to pump, in minutes. 0 is off.
///
/// The same ladder the feed interval offers, minus the 3.5-hour rung nobody
/// picked, and with an explicit Off at the top: a pumping schedule is a
/// choice, not something every household has.
const pumpIntervalOptions = <int>[0, 90, 120, 150, 180, 240, 300, 360];

const _pumpIntervalKey = 'pump_interval_minutes';

/// What this device last confirmed the account's copy holds.
///
/// Not the same as the chosen value: a change that never reached Firestore
/// leaves the two apart, which is how [adoptedSetting] tells an unpushed
/// local change from a change made on another device.
const _pumpIntervalSyncedKey = 'pump_interval_synced';

/// The caregiver's pumping cadence, or 0 when they have not set one.
///
/// Off by default, which is the opposite of the feed reminder and
/// deliberately so. A feeding rhythm is the baby's and the app can see it in
/// the log; a pumping rhythm is the caregiver's own, and it varies from
/// every three hours round the clock to twice a day to whenever there is a
/// spare twenty minutes. Guessing one and counting down to it would invent a
/// schedule and then nag about missing it.
///
/// Stored twice, and follows the account rather than the device. Local
/// preferences stay the immediate answer — there is no loading state to sit
/// through and the dropdown has to work offline — while the account's copy
/// is what a second device reads. The two are reconciled in [_reconcile],
/// which is the same three-way merge the feed interval runs (#27): a device
/// carrying a change the account never acknowledged keeps it and pushes
/// again, and otherwise the account wins.
///
/// Unlike the feed interval, nothing server-side reads this. It is synced
/// because a caregiver who sets their cadence on a phone means it on the
/// tablet too, not because a Cloud Function is waiting for it — there is no
/// pump notification.
final pumpIntervalProvider = NotifierProvider<PumpIntervalNotifier, int>(
  PumpIntervalNotifier.new,
);

class PumpIntervalNotifier extends Notifier<int> {
  @override
  int build() {
    ref.listen(notificationPrefsProvider, (_, next) {
      final remote = next.value;
      if (remote != null) _reconcile(remote);
    }, fireImmediately: true);

    return ref.read(sharedPreferencesProvider).getInt(_pumpIntervalKey) ?? 0;
  }

  /// Takes the account's cadence when it is the newer one, and pushes this
  /// device's again when it is not.
  Future<void> _reconcile(NotificationPrefs remote) async {
    // Signed out, the stream emits defaults rather than the account's
    // values. Adopting those would read as the account asking to turn the
    // countdown off every time someone signs out.
    if (!ref.read(hasAccountPrefsProvider)) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final chosen = prefs.getInt(_pumpIntervalKey);
    final synced = prefs.getInt(_pumpIntervalSyncedKey);

    final interval = adoptedSetting(
      chosen: chosen,
      lastSynced: synced,
      server: remote.pumpIntervalMinutes,
    );

    if (interval == null) {
      // Nothing to take. If this device is holding a change the account
      // never acknowledged, this is the moment to try pushing it again —
      // otherwise a sync that failed once would stay failed until the
      // setting was next touched by hand.
      if (chosen != null && chosen != synced) await _syncToServer();
      return;
    }

    state = interval;
    // Written back as the chosen value and as the acknowledged one together:
    // this device now agrees with the account and has nothing to push.
    await prefs.setInt(_pumpIntervalKey, interval);
    await prefs.setInt(_pumpIntervalSyncedKey, interval);
  }

  Future<void> setMinutes(int minutes) async {
    state = minutes;
    await ref.read(sharedPreferencesProvider).setInt(_pumpIntervalKey, minutes);
    await _syncToServer();
  }

  /// Best-effort. The local value is what Home reads, so a failed sync
  /// leaves the caregiver's choice standing and the unacknowledged marker
  /// behind for [_reconcile] to retry from.
  Future<void> _syncToServer() async {
    final repo = ref.read(notificationPrefsRepositoryProvider);
    if (repo == null) return;
    final minutes = state;
    try {
      await repo.savePumpCadence(intervalMinutes: minutes);
    } catch (_) {
      return;
    }
    await ref
        .read(sharedPreferencesProvider)
        .setInt(_pumpIntervalSyncedKey, minutes);
  }
}

/// When the next pump is due, or null when there is nothing to count to.
///
/// Null in two cases, and they are different things: no cadence set, so the
/// caregiver has not asked for a countdown; or nothing pumped yet, so there
/// is no point to measure from. Either way the Home row falls back to saying
/// when the last session was, which is what it said before this existed.
///
/// Measured from the last session rather than from a fixed clock time. The
/// feed interval anchors the same way, and for the same reason: pumping an
/// hour late should push the next one out, not leave it immediately overdue.
final nextPumpDueProvider = Provider<DateTime?>((ref) {
  final minutes = ref.watch(pumpIntervalProvider);
  if (minutes <= 0) return null;
  final last = ref.watch(lastPumpingProvider);
  if (last == null) return null;
  return last.time.add(Duration(minutes: minutes));
});
