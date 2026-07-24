import 'package:baby_app/features/timeline/timeline_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimelineFormat.dayLabel', () {
    final now = DateTime(2026, 7, 23, 15, 0);

    test('today / yesterday / tomorrow', () {
      expect(TimelineFormat.dayLabel(DateTime(2026, 7, 23), now: now), 'Today');
      expect(
        TimelineFormat.dayLabel(DateTime(2026, 7, 22), now: now),
        'Yesterday',
      );
      expect(
        TimelineFormat.dayLabel(DateTime(2026, 7, 24), now: now),
        'Tomorrow',
      );
    });

    test('older dates show weekday and month', () {
      // 2026-07-20 is a Monday.
      expect(
        TimelineFormat.dayLabel(DateTime(2026, 7, 20), now: now),
        'Mon, Jul 20',
      );
    });
  });

  group('TimelineFormat.interval', () {
    test('formats hours and minutes', () {
      expect(TimelineFormat.interval(90), '1h 30m');
      expect(TimelineFormat.interval(45), '45m');
      expect(TimelineFormat.interval(120), '2h');
      expect(TimelineFormat.interval(null), '—');
    });
  });

  group('TimelineFormat.ml', () {
    test('trims whole numbers', () {
      expect(TimelineFormat.ml(120), '120');
      expect(TimelineFormat.ml(12.5), '12.5');
    });
  });
}
