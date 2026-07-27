/// Formatting helpers for the timeline, kept pure for unit testing.
abstract final class TimelineFormat {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "Today" / "Yesterday" / "Mon, Jul 21". [now] is injectable for tests.
  static String dayLabel(DateTime day, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final target = DateTime(day.year, day.month, day.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return '${_weekdays[target.weekday - 1]}, '
        '${_months[target.month - 1]} ${target.day}';
  }

  /// Whether two instants fall on the same calendar day.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// "Jul 24" — a compact date used to stamp rows that aren't from today.
  static String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  /// Minutes → "2h 30m" / "45m" / "—" when null.
  static String interval(int? minutes) {
    if (minutes == null) return '—';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// Trims trailing ".0" from whole-number millilitre totals.
  static String ml(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
