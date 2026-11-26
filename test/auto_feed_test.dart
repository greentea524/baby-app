import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/care_stay.dart';
import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/milk_kind.dart';
import 'package:baby_app/features/away/auto_feed.dart';

/// When the app logs a feed by itself while the baby is in someone else's
/// care.
void main() {
  final drop = DateTime(2026, 11, 26, 8, 0);
  DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 26, h, m);

  CareStay stay({
    DateTime? pickedUp,
    DateTime? autoUntil,
    bool auto = true,
    int interval = 180,
  }) => CareStay(
    id: 's1',
    droppedAt: drop,
    pickedUpAt: pickedUp,
    carer: 'Grandparents',
    autoFeed: auto,
    amountMl: 120,
    milk: MilkKind.expressed,
    intervalMinutes: interval,
    autoUntil: autoUntil,
  );

  test('one each interval after the last feed, up to now', () {
    // Fed at 7, dropped off at 8: due at 10, 1 and 4.
    expect(autoFeedTimes(stay: stay(), lastFeed: at(7), until: at(17)), [
      at(10),
      at(13),
      at(16),
    ]);
  });

  test('nothing before the first is due', () {
    expect(
      autoFeedTimes(stay: stay(), lastFeed: at(7), until: at(9, 59)),
      isEmpty,
    );
  });

  test('a feed logged by hand while away moves the next one', () {
    // Grandma texted that she fed at 10:30.
    expect(autoFeedTimes(stay: stay(), lastFeed: at(10, 30), until: at(14)), [
      at(13, 30),
    ]);
  });

  test('a baby overdue at drop-off has the first at drop-off', () {
    expect(autoFeedTimes(stay: stay(), lastFeed: at(3), until: at(9)), [drop]);
  });

  test('none after pick-up', () {
    expect(
      autoFeedTimes(
        stay: stay(pickedUp: at(12)),
        lastFeed: at(7),
        until: at(20),
      ),
      [at(10)],
    );
  });

  test('a feed deleted by hand is not put back', () {
    // The 10 o'clock one was logged, then deleted: the last feed is 7 again,
    // but the stay has already got as far as 10.
    expect(
      autoFeedTimes(
        stay: stay(autoUntil: at(10)),
        lastFeed: at(7),
        until: at(14),
      ),
      [at(13)],
    );
  });

  test('nothing when automatic feeds are off', () {
    expect(
      autoFeedTimes(stay: stay(auto: false), lastFeed: at(7), until: at(20)),
      isEmpty,
    );
  });

  test('a stay left open for days fills in a bounded amount at a time', () {
    final times = autoFeedTimes(
      stay: stay(interval: 60),
      lastFeed: at(7),
      until: drop.add(const Duration(days: 7)),
    );
    expect(times, hasLength(autoFeedCap));
  });

  test(
    'each is a bottle of the amount and milk chosen, marked as automatic',
    () {
      final feed = autoFeedAt(stay(), at(10));
      expect(feed.type, FeedingType.bottle);
      expect(feed.amountMl, 120);
      expect(feed.milk, MilkKind.expressed);
      expect(feed.notes, 'Auto-logged · with Grandparents');
      expect(feed.drivesFeedClock, isTrue);
      expect(isAutoFeed(feed), isTrue);
      // The same id on every device, so two filling it in write one feed.
      expect(feed.id, autoFeedId(stay(), at(10)));
      expect(
        isAutoFeed(
          FeedingEvent(id: 'abc', type: FeedingType.bottle, startTime: at(9)),
        ),
        isFalse,
      );
    },
  );
}
