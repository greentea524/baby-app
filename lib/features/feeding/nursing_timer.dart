import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/feeding_event.dart' show BreastSide;

const _key = 'nursing_timer';

/// A breastfeed being timed, kept on the device so it outlives the sheet
/// (#43). Closing the sheet by accident, or the phone locking mid-feed, used
/// to throw the session away; now reopening Breastfeeding picks it up where
/// it was, still running if it was running.
class NursingTimer {
  const NursingTimer({
    required this.startedAt,
    required this.elapsed,
    required this.side,
    this.runningSince,
  });

  /// When the feed began: the start of its first run.
  final DateTime startedAt;

  /// Time counted before the current run.
  final Duration elapsed;

  /// When the current run started, or null while paused.
  final DateTime? runningSince;

  final BreastSide side;

  bool get running => runningSince != null;

  /// All the time counted, up to [now].
  Duration total(DateTime now) =>
      running ? elapsed + now.difference(runningSince!) : elapsed;

  Map<String, Object?> toJson() => {
    'startedAt': startedAt.millisecondsSinceEpoch,
    'elapsedMs': elapsed.inMilliseconds,
    'runningSince': runningSince?.millisecondsSinceEpoch,
    'side': side.name,
  };

  static NursingTimer? fromJson(Map<String, dynamic> j) {
    final started = j['startedAt'];
    if (started is! int) return null;
    final since = j['runningSince'];
    return NursingTimer(
      startedAt: DateTime.fromMillisecondsSinceEpoch(started),
      elapsed: Duration(milliseconds: (j['elapsedMs'] as int?) ?? 0),
      runningSince: since is int
          ? DateTime.fromMillisecondsSinceEpoch(since)
          : null,
      side: BreastSide.values.asNameMap()[j['side']] ?? BreastSide.left,
    );
  }
}

/// The breastfeed being timed on this device, or null.
final nursingTimerProvider =
    NotifierProvider<NursingTimerNotifier, NursingTimer?>(
      NursingTimerNotifier.new,
    );

class NursingTimerNotifier extends Notifier<NursingTimer?> {
  @override
  NursingTimer? build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return null;
    try {
      return NursingTimer.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void set(NursingTimer? timer) {
    state = timer;
    final prefs = ref.read(sharedPreferencesProvider);
    unawaited(
      timer == null
          ? prefs.remove(_key)
          : prefs.setString(_key, jsonEncode(timer.toJson())),
    );
  }
}
