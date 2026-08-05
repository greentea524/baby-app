import '../../data/models/feeding_event.dart';

/// How often the baby has been feeding lately. Informational only.
///
/// This used to drive the reminder itself (KAN-154), and doing so made the
/// alarm unpredictable: a single rolling statistic can't describe a rhythm
/// that is 3-hourly by day and 6-hourly at night, so daytime reminders ran
/// late and the first night reminder fired hours early. The reminder is now a
/// fixed interval the caregiver sets; this number exists to tell them what to
/// set it to.
class FeedRhythm {
  const FeedRhythm({required this.typicalGapMinutes, required this.samples});

  /// The median gap between recent feeds, or null without enough history.
  final int? typicalGapMinutes;

  /// How many gaps that median was taken over — 0 means nothing to show.
  final int samples;

  bool get hasRhythm => typicalGapMinutes != null;

  static const none = FeedRhythm(typicalGapMinutes: null, samples: 0);
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

/// Whether an event drives the milk clock. Lives on the model, since the daily
/// stats need the same rule; kept here as a function so the reminder code
/// reads the way it always has.
bool drivesFeedClock(FeedingEvent f) => f.drivesFeedClock;

/// Drops the events that shouldn't reset or reshape the feeding clock.
///
/// Falls back to the full list when those are all there is to go on: a
/// caregiver who has only logged top-ups or solids still deserves a reminder,
/// and going silent is the more dangerous failure. Needs two survivors to be
/// useful, since a single feed yields no interval.
List<FeedingEvent> _clockFeeds(List<FeedingEvent> feedings) {
  final milkFeeds = feedings.where(drivesFeedClock).toList();
  return milkFeeds.length >= 2 ? milkFeeds : feedings;
}

/// The gaps between recent clock feeds, in minutes, oldest first.
///
/// Uses at most the last [window] gaps so the figure tracks the baby's current
/// rhythm rather than being dragged by older newborn patterns, and ignores
/// gaps under [minGapMinutes] as same-session entries.
List<int> recentFeedGaps(
  List<FeedingEvent> feedings, {
  int window = 8,
  int minGapMinutes = sameSessionMinutes,
}) {
  final clockFeeds = _clockFeeds(feedings);
  if (clockFeeds.length < 2) return const [];

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
  // noise — better to report it than to report nothing.
  if (gaps.isEmpty) gaps = allGaps;

  return gaps.length <= window ? gaps : gaps.sublist(gaps.length - window);
}

/// How often the baby has been feeding lately, as a median gap.
///
/// Median rather than mean, because feeding is not one rhythm but two. On a
/// 3-hourly day with a single 6-hour night, the mean lands at 206 minutes —
/// describing neither half — while the median reports the 180 the day
/// actually runs at, treating the night stretch as the outlier it is.
FeedRhythm feedRhythm(
  List<FeedingEvent> feedings, {
  int window = 8,
  int minGapMinutes = sameSessionMinutes,
}) {
  final gaps = recentFeedGaps(
    feedings,
    window: window,
    minGapMinutes: minGapMinutes,
  );
  if (gaps.isEmpty) return FeedRhythm.none;

  final sorted = [...gaps]..sort();
  final mid = sorted.length ~/ 2;
  final median = sorted.length.isOdd
      ? sorted[mid]
      : ((sorted[mid - 1] + sorted[mid]) / 2).round();

  return FeedRhythm(typicalGapMinutes: median, samples: sorted.length);
}

/// The next feed time for a fixed-interval reminder (KAN-155): simply the
/// last full feed plus the configured gap.
///
/// Snacks and solids are skipped. A fixed interval is usually set as a safety
/// floor ("don't go more than 4 hours"), so letting a 10 ml top-up or a bowl
/// of purée push it out by a whole interval would fail in the dangerous
/// direction.
DateTime? fixedIntervalDue(List<FeedingEvent> feedings, int intervalMinutes) {
  if (feedings.isEmpty) return null;
  final milkFeeds = feedings.where(drivesFeedClock);
  // Only top-ups or solids so far — still better to remind than stay silent.
  final anchors = milkFeeds.isEmpty ? feedings : milkFeeds;
  final latest = anchors
      .map((f) => f.startTime)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return latest.add(Duration(minutes: intervalMinutes));
}

/// How close the next feed is, for anything that wants to colour it.
enum FeedDueState {
  /// Far enough off to be background information.
  upcoming,

  /// Close enough to start getting ready — within [feedDueSoonWindow].
  soon,

  /// Due, or past it.
  overdue,
}

/// How long before a feed is due that it starts reading as imminent.
///
/// Roughly the notice a caregiver needs to act on it: long enough to warm a
/// bottle or settle into a chair, short enough that the chip is not amber for
/// most of the gap between feeds.
const Duration feedDueSoonWindow = Duration(minutes: 15);

/// Where [due] sits relative to [now].
///
/// Both boundaries are inclusive: a feed due exactly now reads as overdue
/// rather than soon, and one exactly [within] away is already soon. The
/// countdown beside it is rounded to whole minutes, so a state that flipped a
/// second either side of the label would contradict it.
FeedDueState feedDueState(
  DateTime due, {
  required DateTime now,
  Duration within = feedDueSoonWindow,
}) {
  if (!due.isAfter(now)) return FeedDueState.overdue;
  return due.difference(now) <= within
      ? FeedDueState.soon
      : FeedDueState.upcoming;
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
