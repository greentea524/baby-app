import '../../data/models/feeding_event.dart';

/// A prediction of when the next feed is due (KAN-154).
class FeedPrediction {
  const FeedPrediction({
    required this.nextDue,
    required this.averageIntervalMinutes,
    required this.intervalSamples,
    required this.lastFeedAt,
  });

  /// When the next feed is expected, or null if there isn't enough history.
  final DateTime? nextDue;

  /// The rolling-average gap between feeds, in minutes.
  final int? averageIntervalMinutes;

  /// How many gaps the average was computed from — 0 means no prediction.
  final int intervalSamples;

  final DateTime? lastFeedAt;

  bool get hasPrediction => nextDue != null;

  /// Empty prediction, used when there's no history or reminders are off.
  static const none = FeedPrediction(
    nextDue: null,
    averageIntervalMinutes: null,
    intervalSamples: 0,
    lastFeedAt: null,
  );
}

/// Predicts the next feed from a rolling average of recent intervals.
///
/// Uses at most the last [window] gaps so the estimate tracks the baby's
/// current rhythm rather than being dragged by older newborn patterns.
/// Needs at least two feeds (one gap) to predict anything.
FeedPrediction predictNextFeed(List<FeedingEvent> feedings, {int window = 8}) {
  if (feedings.length < 2) {
    return FeedPrediction(
      nextDue: null,
      averageIntervalMinutes: null,
      intervalSamples: 0,
      lastFeedAt: feedings.isEmpty ? null : feedings.first.startTime,
    );
  }

  final sorted = [...feedings]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final gaps = <int>[];
  for (var i = 1; i < sorted.length; i++) {
    gaps.add(sorted[i].startTime.difference(sorted[i - 1].startTime).inMinutes);
  }
  final recent = gaps.length <= window
      ? gaps
      : gaps.sublist(gaps.length - window);

  final average = (recent.reduce((a, b) => a + b) / recent.length).round();
  final lastAt = sorted.last.startTime;

  return FeedPrediction(
    nextDue: lastAt.add(Duration(minutes: average)),
    averageIntervalMinutes: average,
    intervalSamples: recent.length,
    lastFeedAt: lastAt,
  );
}

/// The next feed time for a fixed-interval reminder (KAN-155): simply the
/// last feed plus the configured gap.
DateTime? fixedIntervalDue(List<FeedingEvent> feedings, int intervalMinutes) {
  if (feedings.isEmpty) return null;
  final latest = feedings
      .map((f) => f.startTime)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return latest.add(Duration(minutes: intervalMinutes));
}

/// Human countdown to [due]: "in 1h 20m", "due now", "25m overdue".
String countdownLabel(DateTime due, {DateTime? now}) {
  final diff = due.difference(now ?? DateTime.now());
  final minutes = diff.inMinutes;
  if (minutes == 0) return 'due now';
  final magnitude = minutes.abs();
  final h = magnitude ~/ 60;
  final m = magnitude % 60;
  final span = h == 0
      ? '${m}m'
      : m == 0
      ? '${h}h'
      : '${h}h ${m}m';
  return minutes > 0 ? 'in $span' : '$span overdue';
}
