import '../../data/models/feeding_event.dart';

/// One plotted feed: which row it belongs to and where in the day it sits.
typedef FeedDot = ({
  /// Row index, 0 = the most recent day.
  int dayIndex,

  /// Position within the day, 0.0 at midnight through 1.0 at the next.
  double dayFraction,
  FeedingEvent event,
});

/// A day's worth of dots, newest day first.
typedef FeedClockRow = ({DateTime day, List<FeedDot> dots});

/// Where in its day [t] falls, as a fraction — 0.0 at midnight, 0.5 at noon.
///
/// Minute resolution rather than millisecond: the chart is a few hundred
/// pixels wide, so anything finer is invisible and only costs precision in
/// tests.
double dayFraction(DateTime t) => (t.hour * 60 + t.minute) / (24 * 60);

/// Lays feeds out as one row per calendar day from [start] to [end)
/// (exclusive), newest first.
///
/// Every day in the window gets a row, including quiet ones — a gap in the
/// rhythm is exactly the thing this chart exists to show, so collapsing empty
/// days would hide it.
List<FeedClockRow> feedClockRows({
  required DateTime start,
  required DateTime end,
  required List<FeedingEvent> feedings,
}) {
  DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  final days = <DateTime>[];
  for (
    var day = dayOf(end).subtract(const Duration(days: 1));
    !day.isBefore(dayOf(start));
    day = DateTime(day.year, day.month, day.day - 1)
  ) {
    days.add(day);
  }

  final byDay = <DateTime, List<FeedingEvent>>{};
  for (final f in feedings) {
    byDay.putIfAbsent(dayOf(f.startTime), () => []).add(f);
  }
  // Sort the real lists, not the empty-day fallback below — that one is const
  // and sorting it throws.
  for (final list in byDay.values) {
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  return [
    for (var i = 0; i < days.length; i++)
      (
        day: days[i],
        dots: [
          for (final f in byDay[days[i]] ?? const <FeedingEvent>[])
            (dayIndex: i, dayFraction: dayFraction(f.startTime), event: f),
        ],
      ),
  ];
}

/// The longest stretch without a feed across [rows], in minutes, or null when
/// there are fewer than two feeds to measure between.
///
/// Measured across the whole window rather than per day, so an overnight gap
/// isn't cut in half by midnight — which is the gap people actually care
/// about.
int? longestGapMinutes(List<FeedClockRow> rows) {
  final times = <DateTime>[
    for (final row in rows)
      for (final dot in row.dots) dot.event.startTime,
  ]..sort();
  if (times.length < 2) return null;

  var longest = 0;
  for (var i = 1; i < times.length; i++) {
    final gap = times[i].difference(times[i - 1]).inMinutes;
    if (gap > longest) longest = gap;
  }
  return longest;
}
