import 'package:baby_app/features/reminders/feed_prediction.dart';
import 'package:flutter_test/flutter_test.dart';

/// The depleting bar's fill, beside the countdown it has to agree with.
void main() {
  final now = DateTime(2026, 9, 17, 12, 0);
  const interval = Duration(hours: 3);

  double? at(Duration untilDue) =>
      feedRemaining(due: now.add(untilDue), interval: interval, now: now);

  // The bar runs on past the due time: an hour of red, then half an hour
  // of purple. 3h + 1h + 30m.
  const span = 270.0;

  test('full just after a feed, a third left when due', () {
    expect(at(interval), 1.0);
    expect(at(Duration.zero), closeTo(90 / span, 1e-9));
    expect(
      at(Duration.zero),
      closeTo(dueOverdueShare(interval: interval)!, 1e-9),
      reason: 'the due time is where the red starts',
    );
  });

  test('halfway through the gap', () {
    expect(
      at(const Duration(hours: 1, minutes: 30)),
      closeTo(180 / span, 1e-9),
    );
  });

  test('an hour overdue is where purple starts', () {
    expect(
      at(const Duration(hours: -1)),
      closeTo(dueLateShare(interval: interval)!, 1e-9),
    );
  });

  test('hours late keeps a sliver of purple, never negative', () {
    // An empty bar would say nothing about a feed that is hours late.
    final sliver = at(const Duration(hours: -40))!;
    expect(sliver, greaterThan(0));
    expect(sliver, lessThan(dueLateShare(interval: interval)!));
    expect(at(const Duration(hours: -2)), sliver);
  });

  test('nothing to count towards draws nothing', () {
    // An empty bar would say "due now" when it means "no idea".
    expect(feedRemaining(due: null, interval: interval, now: now), isNull);
  });

  test('a nonsense interval draws nothing rather than dividing by zero', () {
    expect(feedRemaining(due: now, interval: Duration.zero, now: now), isNull);
  });
}
