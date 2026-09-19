import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../data/repositories/repository_providers.dart';

/// How often the caregiver means to pump, in minutes. 0 is off.
///
/// The same ladder the feed interval offers, minus the 3.5-hour rung nobody
/// picked, and with an explicit Off at the top: a pumping schedule is a
/// choice, not something every household has.
const pumpIntervalOptions = <int>[0, 90, 120, 150, 180, 240, 300, 360];

const _pumpIntervalKey = 'pump_interval_minutes';

/// The caregiver's pumping cadence, or 0 when they have not set one.
///
/// Off by default, which is the opposite of the feed reminder and
/// deliberately so. A feeding rhythm is the baby's and the app can see it in
/// the log; a pumping rhythm is the caregiver's own, and it varies from
/// every three hours round the clock to twice a day to whenever there is a
/// spare twenty minutes. Guessing one and counting down to it would invent a
/// schedule and then nag about missing it.
///
/// Device-local, unlike the feed interval, because nothing else reads it.
/// The feed interval is mirrored to Firestore so the reminder Cloud Function
/// can work out when a feed is overdue (#27); there is no pump notification,
/// so this number's only consumer is the Home row on this device — and a
/// value synced for no reader is a migration and a reconcile to maintain for
/// nothing. The cost is real and worth naming: a second device shows its own
/// cadence until it is set there too.
final pumpIntervalProvider = NotifierProvider<PumpIntervalNotifier, int>(
  PumpIntervalNotifier.new,
);

class PumpIntervalNotifier extends Notifier<int> {
  @override
  int build() =>
      ref.read(sharedPreferencesProvider).getInt(_pumpIntervalKey) ?? 0;

  Future<void> setMinutes(int minutes) async {
    state = minutes;
    await ref.read(sharedPreferencesProvider).setInt(_pumpIntervalKey, minutes);
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
