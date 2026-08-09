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
    final weeks = days ~/ 7;
    return weeks == 1 ? '1 week old' : '$weeks weeks old';
  }
  if (months < 24) return '$months months old';

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
int _daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// Whole calendar months, so a baby born on the 15th turns a month older on
/// the 15th rather than after some average number of days.
int _monthsBetween(DateTime from, DateTime to) {
  var months = (to.year - from.year) * 12 + (to.month - from.month);
  // The day of the month has not come round yet, so the last month is not
  // complete.
  if (to.day < from.day) months--;
  return months;
}
