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

/// Gaps shorter than this are treated as the same feeding session rather than
/// a new one (KAN-184).
///
/// Topping up a bottle, logging each breast separately, or correcting an
/// entry all produce two records minutes apart. Counting those as feeding
/// intervals drags the rolling average down and makes every later reminder
/// fire early — a single one-minute gap in a 78-minute rhythm pulls the
/// prediction forward by ten minutes.
const int sameSessionMinutes = 20;

/// Drops snacks, which shouldn't reset or reshape the feeding clock.
///
/// Falls back to the full list when snacks are all there is to go on: a
/// caregiver who has only logged top-ups still deserves a reminder, and going
/// silent is the more dangerous failure. Needs two survivors to be useful,
/// since a single feed yields no interval.
List<FeedingEvent> _clockFeeds(List<FeedingEvent> feedings) {
  final fullFeeds = feedings.where((f) => !f.isSnack).toList();
  return fullFeeds.length >= 2 ? fullFeeds : feedings;
}

/// Predicts the next feed from a rolling average of recent intervals.
///
/// Uses at most the last [window] gaps so the estimate tracks the baby's
/// current rhythm rather than being dragged by older newborn patterns, and
/// ignores gaps under [minGapMinutes] as same-session entries.
/// Needs at least two feeds (one gap) to predict anything.
FeedPrediction predictNextFeed(
  List<FeedingEvent> feedings, {
  int window = 8,
  int minGapMinutes = sameSessionMinutes,
}) {
  // Snacks are dropped up front so they neither contribute intervals nor
  // become the anchor the next feed is projected from.
  final clockFeeds = _clockFeeds(feedings);

  if (clockFeeds.length < 2) {
    return FeedPrediction(
      nextDue: null,
      averageIntervalMinutes: null,
      intervalSamples: 0,
      lastFeedAt: clockFeeds.isEmpty ? null : clockFeeds.first.startTime,
    );
  }

  final sorted = [...clockFeeds]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final allGaps = <int>[];
  for (var i = 1; i < sorted.length; i++) {
    allGaps.add(
      sorted[i].startTime.difference(sorted[i - 1].startTime).inMinutes,
    );
  }

  // Filter before windowing, so same-session entries don't consume slots that
  // real intervals should occupy.
  var gaps = allGaps.where((g) => g >= minGapMinutes).toList();
  // Every gap being short is a genuine cluster-feeding stretch, not logging
  // noise — better to predict from it than to refuse to predict at all.
  if (gaps.isEmpty) gaps = allGaps;

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
/// last full feed plus the configured gap.
///
/// Snacks are skipped. A fixed interval is usually set as a safety floor
/// ("don't go more than 4 hours"), so letting a 10 ml top-up push it out by a
/// whole interval would fail in the dangerous direction.
DateTime? fixedIntervalDue(List<FeedingEvent> feedings, int intervalMinutes) {
  if (feedings.isEmpty) return null;
  final fullFeeds = feedings.where((f) => !f.isSnack);
  // Only top-ups logged so far — still better to remind than to stay silent.
  final anchors = fullFeeds.isEmpty ? feedings : fullFeeds;
  final latest = anchors
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
