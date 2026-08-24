import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/repositories/baby_data.dart';

/// What the delete confirmation says is about to go (#28).
///
/// "This cannot be undone" is true of every destructive dialog ever written
/// and reads as boilerplate. A number is what makes someone stop, so these
/// sentences are worth reading as prose.
void main() {
  group('the sentence', () {
    test('names one thing plainly', () {
      expect(BabyData.describe({'feedings': 12}), '12 feeds');
    });

    test('joins two with "and", not a comma', () {
      expect(
        BabyData.describe({'feedings': 12, 'diapers': 9}),
        '12 feeds and 9 diaper changes',
      );
    });

    test('and a longer list the way a person would read it out', () {
      expect(
        BabyData.describe({
          'feedings': 1284,
          'diapers': 903,
          'growth': 12,
          'appointments': 4,
        }),
        '1284 feeds, 903 diaper changes, 12 growth measurements and '
        '4 appointments',
      );
    });

    test('is singular where it matters', () {
      // "1 feeds" is the giveaway of a string built without listening to it.
      expect(
        BabyData.describe({'feedings': 1, 'growth': 1, 'pumps': 1}),
        '1 feed, 1 growth measurement and 1 pumping session',
      );
    });

    test('keeps a fixed order however the counts arrive', () {
      // Map order follows insertion, and countAll walks the collections in
      // its own order — so the sentence must not depend on either.
      expect(
        BabyData.describe({'growth': 2, 'feedings': 5}),
        '5 feeds and 2 growth measurements',
      );
    });

    test('leaves invites out of the count', () {
      // A pending invitation is not a record of anything that happened, and
      // listing it beside 900 feeds reads as noise.
      expect(BabyData.describe({'feedings': 3, 'invites': 2}), '3 feeds');
    });

    test('says so when there is nothing logged, rather than nothing at all', () {
      // The sentence it lands in is "Permanently delete …, along with Ada's
      // profile", so this half still has to read.
      expect(BabyData.describe(const {}), 'no logged entries');
      expect(BabyData.describe({'invites': 1}), 'no logged entries');
    });
  });

  group('what gets swept', () {
    test('is every subcollection the rules name, and invites', () {
      // Named rather than discovered: a wildcard sweep would be the same
      // mistake as the wildcard rule it replaced (#22), in the other
      // direction. If a new event type is added, it belongs here too — this
      // test is the reminder.
      expect(BabyData.collections, [
        'feedings',
        'diapers',
        'growth',
        'pumps',
        'appointments',
        'invites',
      ]);
    });
  });
}
