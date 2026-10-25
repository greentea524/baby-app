import 'package:flutter/material.dart';

import '../../data/models/daily_check.dart';

/// The picture for each [ChecklistIcon].
IconData checklistIcon(ChecklistIcon icon) => switch (icon) {
  ChecklistIcon.vitamin => Icons.wb_sunny_outlined,
  ChecklistIcon.tummyTime => Icons.child_care,
  ChecklistIcon.bath => Icons.bathtub_outlined,
  ChecklistIcon.probiotic => Icons.science_outlined,
  ChecklistIcon.iron => Icons.medication_outlined,
  ChecklistIcon.outside => Icons.park_outlined,
  ChecklistIcon.other => Icons.check_circle_outline,
};

/// Midnight at the start of [t]'s day, on this phone's clock.
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Midnight [n] days before [day]'s. By the calendar rather than by 24-hour
/// steps, which would land an hour off across a clock change.
DateTime daysBefore(DateTime day, int n) =>
    DateTime(day.year, day.month, day.day - n);

/// The first tick of each item on [day], by item id.
///
/// The first, because two caregivers can tick the same item at once and
/// both writes land; the earlier is when it was done.
Map<String, DailyCheck> ticksOn(List<DailyCheck> checks, DateTime day) {
  final start = dayOf(day);
  final end = daysBefore(start, -1);
  final ticks = <String, DailyCheck>{};
  for (final c in checks) {
    if (c.time.isBefore(start) || !c.time.isBefore(end)) continue;
    final seen = ticks[c.itemId];
    if (seen == null || c.time.isBefore(seen.time)) ticks[c.itemId] = c;
  }
  return ticks;
}

/// How many times each item was ticked on [day], by item id.
Map<String, int> countsOn(List<DailyCheck> checks, DateTime day) {
  final start = dayOf(day);
  final end = daysBefore(start, -1);
  final counts = <String, int>{};
  for (final c in checks) {
    if (c.time.isBefore(start) || !c.time.isBefore(end)) continue;
    counts[c.itemId] = (counts[c.itemId] ?? 0) + 1;
  }
  return counts;
}

/// Every tick of [itemId] on [day] — what unticking it removes.
List<DailyCheck> ticksOf(List<DailyCheck> checks, String itemId, DateTime day) {
  final start = dayOf(day);
  final end = daysBefore(start, -1);
  return [
    for (final c in checks)
      if (c.itemId == itemId && !c.time.isBefore(start) && c.time.isBefore(end))
        c,
  ];
}

/// How many times [itemId] was ticked each day, keyed by midnight.
Map<DateTime, int> _dailyCounts(List<DailyCheck> checks, String itemId) {
  final counts = <DateTime, int>{};
  for (final c in checks) {
    if (c.itemId != itemId) continue;
    final day = dayOf(c.time);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
}

/// How many days in a row [itemId] has been done — ticked [perDay] times —
/// up to [now].
///
/// Today not done yet does not break it: the day is not over. So a streak
/// counts back from today when today is done, and from yesterday when it
/// is not — and is nought only once a whole day has gone by short.
int streak(
  List<DailyCheck> checks,
  String itemId,
  DateTime now, {
  int perDay = 1,
}) {
  final counts = _dailyCounts(checks, itemId);
  bool done(DateTime day) => (counts[day] ?? 0) >= perDay;
  final today = dayOf(now);
  var day = done(today) ? today : daysBefore(today, 1);
  var n = 0;
  while (done(day)) {
    n++;
    day = daysBefore(day, 1);
  }
  return n;
}

/// How much of [itemId] was done on each of the last [count] days, oldest
/// first, ending today: 1 for done, a fraction for part of [perDay].
List<double> recentDays(
  List<DailyCheck> checks,
  String itemId,
  DateTime now, {
  int perDay = 1,
  int count = 7,
}) {
  final counts = _dailyCounts(checks, itemId);
  final today = dayOf(now);
  return [
    for (var i = count - 1; i >= 0; i--)
      ((counts[daysBefore(today, i)] ?? 0) / perDay).clamp(0.0, 1.0),
  ];
}
