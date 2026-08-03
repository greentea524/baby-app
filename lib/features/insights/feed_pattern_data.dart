import '../../data/models/feeding_event.dart';

/// The two figures behind the feeding-pattern charts on Insights: how long the
/// baby went overnight, and what hours of the day she eats at.
///
/// These replace the feed-times scatter (KAN-185). That chart plotted a dot
/// per feed on a day × hour grid, which showed the raw layout but made you do
/// the arithmetic yourself — "is she stretching out at night?" meant eyeballing
/// the space between dots across rows. Both figures below pre-compute the
/// number instead, so they can be drawn as ordinary bars.

/// Night runs from this hour to [nightEndHour] the next morning.
///
/// A wide window on purpose: the point is to catch the long stretch wherever
/// it lands, and bedtime moves by hours across the first year.
const int nightStartHour = 19;
const int nightEndHour = 7;

/// Whether an event counts towards these charts.
///
/// Milk only — solids sit on a completely different schedule and would smear
/// the by-hour shape without saying anything about the milk rhythm.
///
/// Snacks *are* counted, unlike everywhere else in the app. `drivesFeedClock`
/// excludes them so a 10 ml top-up can't push a reminder out by a full
/// interval; that is a question about the reminder, not about the baby. These
/// charts ask when the baby woke to eat, and a 2 am top-up is a waking.
bool countsAsMilk(FeedingEvent f) => f.type != FeedingType.solids;

/// The longest stretch without a milk feed for the night beginning on each of
/// [days], in minutes. 0 for a night with no measurable stretch.
///
/// A gap belongs to the night its *midpoint* falls in. Anchoring on the
/// midpoint rather than on either end is what makes an unusually early night
/// countable: a baby who feeds at 18:30 and sleeps until 08:00 has a gap that
/// starts before the window and ends after it, and matching on either end
/// alone would score that 14-hour night as nothing at all.
///
/// The consequence is that daytime gaps are excluded, since their midpoints
/// fall in the 07:00–19:00 daylight between two windows. That is the intent —
/// a three-hour afternoon nap is not the number anyone is tracking.
///
/// A night can only be measured once the baby feeds again, so the current
/// night reads 0 until morning.
List<int> nightStretchMinutes({
  required List<DateTime> days,
  required List<FeedingEvent> feedings,
  int startHour = nightStartHour,
  int endHour = nightEndHour,
}) {
  final times = [
    for (final f in feedings)
      if (countsAsMilk(f)) f.startTime,
  ]..sort();

  final stretches = List.filled(days.length, 0);
  if (times.length < 2) return stretches;

  // Windows are keyed by the calendar day the night starts on, so the lookup
  // below stays a map read rather than a scan per gap.
  final windowStart = <DateTime, int>{};
  for (var i = 0; i < days.length; i++) {
    final d = days[i];
    windowStart[DateTime(d.year, d.month, d.day, startHour)] = i;
  }

  for (var i = 1; i < times.length; i++) {
    final gap = times[i].difference(times[i - 1]);
    final mid = times[i - 1].add(
      Duration(milliseconds: gap.inMilliseconds ~/ 2),
    );

    // Which night's window could contain this midpoint: the evening of the
    // midpoint's own day if it is past [startHour], otherwise the evening
    // before.
    final day = DateTime(mid.year, mid.month, mid.day);
    final evening = mid.hour >= startHour
        ? DateTime(day.year, day.month, day.day, startHour)
        : DateTime(day.year, day.month, day.day - 1, startHour);
    final morning = DateTime(
      evening.year,
      evening.month,
      evening.day + 1,
      endHour,
    );
    if (!mid.isBefore(morning)) continue;

    final index = windowStart[evening];
    if (index == null) continue;
    final minutes = gap.inMinutes;
    if (minutes > stretches[index]) stretches[index] = minutes;
  }

  return stretches;
}

/// How many milk feeds started in each hour of the day, across the whole
/// range. Always 24 entries, midnight first.
///
/// Accumulated over the range rather than shown per day: one day's timings are
/// noise, and the shape only becomes readable once a fortnight of them is
/// stacked up.
List<int> feedsByHour(List<FeedingEvent> feedings) {
  final counts = List.filled(24, 0);
  for (final f in feedings) {
    if (countsAsMilk(f)) counts[f.startTime.hour]++;
  }
  return counts;
}

/// "12a", "6a", "12p", "9p" — a compact axis label for an hour of the day.
///
/// Twelve-hour throughout, including where the device is set to 24-hour time:
/// the labels sit at 9 px and there is only room for a subset of the 24, so
/// "12a" carries the two things that matter — the number and which half of the
/// day it is — in fewer pixels than "00" does clearly.
String hourLabel(int hour) {
  final suffix = hour < 12 ? 'a' : 'p';
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h$suffix';
}
