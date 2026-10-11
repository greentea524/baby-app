/// How old the baby is, in the unit a person would actually use.
///
/// Not [ageInMonths], which is a fractional figure for plotting against the
/// WHO standard. "0.4 months" is the right input for a growth curve and the
/// wrong thing to read on a screen.
///
/// The unit changes with age because that is how people talk about it: a
/// newborn is counted in days, then weeks for the first stretch of appointments
/// and vaccinations, then months, then years once "26 months" stops being a
/// natural way to answer the question.
String babyAgeLabel(DateTime birthDate, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = _daysBetween(birthDate, today);

  // A birth date in the future is a typo, not an age. The profile form should
  // stop it, but a bad record already stored should not read as "-3 days".
  if (days < 0) return '';
  if (days == 0) return 'born today';
  if (days < 14) return days == 1 ? '1 day old' : '$days days old';

  final months = _monthsBetween(birthDate, today);
  if (months < 3) {
    // Weeks and the days since, rather than whole weeks alone. A week of
    // age turns on the weekday of the birth, so "11 weeks" read all week
    // and seemed to arrive early: on a Monday, a baby born on a Monday is
    // eleven weeks old, and on the Sunday still eleven weeks and six days.
    final weeks = days ~/ 7;
    final extra = days % 7;
    final w = weeks == 1 ? '1 week' : '$weeks weeks';
    if (extra == 0) return '$w old';
    return '$w ${extra == 1 ? '1 day' : '$extra days'} old';
  }
  if (months < 24) {
    // The weeks since this month began, for the same reason as the weeks
    // and days above: "4 months" held for a whole month and said nothing of
    // how far through it the baby was. Weeks rather than days: "4 months
    // 17 days" is more than anyone counts in.
    final weeks = _daysBetween(_monthsAfter(birthDate, months), today) ~/ 7;
    if (weeks == 0) return '$months months old';
    return '$months months ${weeks == 1 ? '1 week' : '$weeks weeks'} old';
  }

  final years = months ~/ 12;
  final rest = months % 12;
  if (rest == 0) return years == 1 ? '1 year old' : '$years years old';
  return '${years}y ${rest}mo';
}

/// Whole calendar days between two dates.
///
/// Compared in UTC on purpose. A local-time difference across a daylight
/// saving change is 23 or 25 hours, and `inDays` truncates, so a baby born the
/// day before the clocks go forward would read as 0 days old.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Whole calendar months, so a baby born on the 15th turns a month older on
/// the 15th rather than after some average number of days — and one born on
/// the 31st on the last day of a shorter month: see [_monthsAfter].
int _monthsBetween(DateTime from, DateTime to) {
  var months = (to.year - from.year) * 12 + (to.month - from.month);
  // This month's anniversary has not come round yet, so the last month is
  // not complete.
  if (_daysBetween(_monthsAfter(from, months), to) < 0) months--;
  return months;
}

/// The day [from] turns [months] months old: the same day of the month, or
/// the month's last day when it has no such day — a baby born on the 31st
/// turns a month older on 30 April and 28 February, not on 1 May or 3 March.
DateTime _monthsAfter(DateTime from, int months) {
  final first = DateTime.utc(from.year, from.month + months);
  final lastDay = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(
    first.year,
    first.month,
    from.day < lastDay ? from.day : lastDay,
  );
}
