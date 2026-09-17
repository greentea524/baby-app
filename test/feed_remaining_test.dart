import 'package:baby_app/features/reminders/feed_prediction.dart';
import 'package:flutter_test/flutter_test.dart';

/// The depleting bar's fill, beside the countdown it has to agree with.
void main() {
  final now = DateTime(2026, 9, 17, 12, 0);
  const interval = Duration(hours: 3);

  double? at(Duration untilDue) =>
      feedRemaining(due: now.add(untilDue), interval: interval, now: now);

  test('full just after a feed, empty when due', () {
    expect(at(interval), 1.0);
    expect(at(Duration.zero), 0.0);
  });

  test('halfway through the gap is half left', () {
    expect(at(const Duration(hours: 1, minutes: 30)), closeTo(0.5, 0.001));
    expect(at(const Duration(minutes: 45)), closeTo(0.25, 0.001));
  });

  test('overdue reads as empty, not as negative', () {
    // A bar has no room past zero; how far past is the countdown's job.
    expect(at(const Duration(hours: -2)), 0.0);
    expect(at(const Duration(hours: -40)), 0.0);
  });

  test('nothing to count towards draws nothing', () {
    // An empty bar would say "due now" when it means "no idea".
    expect(feedRemaining(due: null, interval: interval, now: now), isNull);
  });

  test('a nonsense interval draws nothing rather than dividing by zero', () {
    expect(feedRemaining(due: now, interval: Duration.zero, now: now), isNull);
  });
}
