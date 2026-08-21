/// What one day looked like, for the Insights day view.
///
/// A day is not a short week. The trend charts plot one bar per day, so at a
/// range of one they collapse to a single bar and say nothing — what a day
/// wants is *when things happened*, not how many.
library;

import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/pumping_event.dart';

/// What kind of event a mark on the 24-hour strip is.
enum DayMarkKind { feed, snack, diaper, pump }

/// One event, placed on the day by the hour it happened — 0.0 at midnight,
/// 13.5 at half past one in the afternoon.
typedef DayMark = ({double hour, DayMarkKind kind});

/// Every event on [day], in time order, as fractional hours.
///
/// Anything outside the day is dropped rather than clamped to an edge: a
/// mark at 00:00 that actually happened yesterday would read as a real
/// event at midnight.
List<DayMark> dayMarks({
  required DateTime day,
  List<FeedingEvent> feedings = const [],
  List<DiaperEvent> diapers = const [],
  List<PumpingEvent> pumps = const [],
}) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));

  double? at(DateTime t) {
    if (t.isBefore(start) || !t.isBefore(end)) return null;
    return t.difference(start).inMinutes / 60;
  }

  final marks = <DayMark>[
    for (final f in feedings)
      if (at(f.startTime) case final h?)
        (hour: h, kind: f.isSnack ? DayMarkKind.snack : DayMarkKind.feed),
    for (final d in diapers)
      if (at(d.time) case final h?) (hour: h, kind: DayMarkKind.diaper),
    for (final p in pumps)
      if (at(p.time) case final h?) (hour: h, kind: DayMarkKind.pump),
  ];
  return marks..sort((a, b) => a.hour.compareTo(b.hour));
}

/// The day's diapers, split by what was in them.
typedef DiaperMix = ({int wet, int dirty, int both});

extension DiaperMixTotals on DiaperMix {
  int get total => wet + dirty + both;

  /// Dirty and mixed together — "has there been a poo today" counts both,
  /// because a mixed diaper is a dirty one that also happened to be wet.
  int get withPoop => dirty + both;
}

DiaperMix diaperMix(List<DiaperEvent> diapers) {
  var wet = 0, dirty = 0, both = 0;
  for (final d in diapers) {
    switch (d.type) {
      case DiaperType.wet:
        wet++;
      case DiaperType.dirty:
        dirty++;
      case DiaperType.both:
        both++;
    }
  }
  return (wet: wet, dirty: dirty, both: both);
}

/// The most recent diaper with something in it, from any day.
///
/// Deliberately not limited to the day being viewed. "None yet today" is
/// alarming at six in the morning and reassuring at six in the evening, and
/// the difference between the two is when the last one actually was — which
/// is the number a parent is really watching.
DiaperEvent? lastWithPoop(List<DiaperEvent> diapers) {
  DiaperEvent? latest;
  for (final d in diapers) {
    if (!d.hasPoop) continue;
    if (latest == null || d.time.isAfter(latest.time)) latest = d;
  }
  return latest;
}
