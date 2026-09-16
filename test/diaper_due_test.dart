import 'package:baby_app/features/diaper/diaper_due.dart';
import 'package:baby_app/features/reminders/feed_prediction.dart';
import 'package:flutter_test/flutter_test.dart';

/// When a diaper card starts asking for attention.
void main() {
  final now = DateTime(2026, 9, 16, 14, 0);
  DueState? at(Duration ago) => diaperDueState(now.subtract(ago), now: now);

  test('a fresh change is background information', () {
    expect(at(Duration.zero), DueState.upcoming);
    expect(at(const Duration(minutes: 90)), DueState.upcoming);
  });

  test('two hours is where it starts saying so', () {
    // The boundary is inclusive, matching the feed clock it borrows: exactly
    // two hours already reads as amber rather than a minute later.
    expect(at(const Duration(hours: 1, minutes: 59)), DueState.upcoming);
    expect(at(const Duration(hours: 2)), DueState.soon);
    expect(at(const Duration(hours: 2, minutes: 59)), DueState.soon);
  });

  test('three hours is overdue, and stays overdue', () {
    expect(at(const Duration(hours: 3)), DueState.overdue);
    expect(at(const Duration(hours: 9)), DueState.overdue);
  });

  test('nothing logged is not overdue, it is empty', () {
    // A card that has never had a change on it would otherwise go red on a
    // household's first morning, over a problem the app invented from its
    // own lack of data.
    expect(diaperDueState(null, now: now), isNull);
  });

  test('the thresholds are the ones asked for', () {
    expect(diaperSoonAfter, const Duration(hours: 2));
    expect(diaperOverdueAfter, const Duration(hours: 3));
  });
}
