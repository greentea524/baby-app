import 'package:flutter/material.dart';

import '../../data/models/daily_check.dart';

/// The picture for each [ChecklistIcon].
///
/// "Other" is an empty circle, not a tick in one: it is what an item shows
/// before it is done, and a tick there read as done already.
IconData checklistIcon(ChecklistIcon icon) => switch (icon) {
  ChecklistIcon.vitamin => Icons.wb_sunny_outlined,
  ChecklistIcon.tummyTime => Icons.child_care,
  ChecklistIcon.bath => Icons.bathtub_outlined,
  ChecklistIcon.probiotic => Icons.science_outlined,
  ChecklistIcon.iron => Icons.medication_outlined,
  ChecklistIcon.outside => Icons.park_outlined,
  ChecklistIcon.other => Icons.circle_outlined,
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

/// What [check] adds towards [item]'s goal: its minutes for a timed item,
/// one for a counted one.
int amountOf(ChecklistItem item, DailyCheck check) =>
    item.timed ? (check.minutes ?? 0) : 1;

/// How far each item got on [day], by item id: minutes for a timed item,
/// times for a counted one.
Map<String, int> progressOn(
  List<DailyCheck> checks,
  List<ChecklistItem> items,
  DateTime day,
) {
  final byId = {for (final i in items) i.id: i};
  final start = dayOf(day);
  final end = daysBefore(start, -1);
  final progress = <String, int>{};
  for (final c in checks) {
    final item = byId[c.itemId];
    if (item == null) continue;
    if (c.time.isBefore(start) || !c.time.isBefore(end)) continue;
    progress[c.itemId] = (progress[c.itemId] ?? 0) + amountOf(item, c);
  }
  return progress;
}

/// How far [item] got each day, keyed by midnight.
Map<DateTime, int> _dailyProgress(List<DailyCheck> checks, ChecklistItem item) {
  final progress = <DateTime, int>{};
  for (final c in checks) {
    if (c.itemId != item.id) continue;
    final day = dayOf(c.time);
    progress[day] = (progress[day] ?? 0) + amountOf(item, c);
  }
  return progress;
}

/// How many days in a row [item] has been done — reached its goal — up to
/// [now].
///
/// Today not done yet does not break it: the day is not over. So a streak
/// counts back from today when today is done, and from yesterday when it
/// is not — and is nought only once a whole day has gone by short.
int streak(List<DailyCheck> checks, ChecklistItem item, DateTime now) {
  final progress = _dailyProgress(checks, item);
  bool done(DateTime day) => (progress[day] ?? 0) >= item.goal;
  final today = dayOf(now);
  var day = done(today) ? today : daysBefore(today, 1);
  var n = 0;
  while (done(day)) {
    n++;
    day = daysBefore(day, 1);
  }
  return n;
}

/// How much of [item] was done on each of the last [count] days, oldest
/// first, ending today: 1 for done, a fraction for part of its goal.
List<double> recentDays(
  List<DailyCheck> checks,
  ChecklistItem item,
  DateTime now, {
  int count = 7,
}) {
  final progress = _dailyProgress(checks, item);
  final today = dayOf(now);
  return [
    for (var i = count - 1; i >= 0; i--)
      ((progress[daysBefore(today, i)] ?? 0) / item.goal).clamp(0.0, 1.0),
  ];
}

/// How much of [item] was done each day, keyed by midnight: 1 for done, a
/// fraction for part of its goal. Days with nothing done are absent.
Map<DateTime, double> dailyShares(
  List<DailyCheck> checks,
  ChecklistItem item,
) => {
  for (final MapEntry(:key, :value) in _dailyProgress(checks, item).entries)
    key: (value / item.goal).clamp(0.0, 1.0),
};

/// The longest run of days in a row [item] was done, anywhere in [checks].
int bestStreak(List<DailyCheck> checks, ChecklistItem item) {
  final done = [
    for (final MapEntry(:key, :value) in _dailyProgress(checks, item).entries)
      if (value >= item.goal) key,
  ]..sort();
  var best = 0;
  var run = 0;
  DateTime? previous;
  for (final day in done) {
    run = previous != null && daysBefore(day, 1) == previous ? run + 1 : 1;
    if (run > best) best = run;
    previous = day;
  }
  return best;
}

/// [item] over the last [count] days ending today: on how many it was done,
/// and how much was done on an average day — minutes for a timed item,
/// times for a counted one.
({int doneDays, double perDay}) rangeSummary(
  List<DailyCheck> checks,
  ChecklistItem item,
  DateTime now, {
  required int count,
}) {
  final progress = _dailyProgress(checks, item);
  final today = dayOf(now);
  var done = 0;
  var total = 0;
  for (var i = 0; i < count; i++) {
    final amount = progress[daysBefore(today, i)] ?? 0;
    total += amount;
    if (amount >= item.goal) done++;
  }
  return (doneDays: done, perDay: total / count);
}
