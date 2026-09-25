import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/milk_kind.dart';

/// The kinds of milk, as stored.
void main() {
  test('the stored names are the ones the Firestore rules accept', () {
    // Changing one of these is a rules change too.
    expect(MilkKind.values.map((k) => k.name), [
      'expressed',
      'formula',
      'wholeMilk',
    ]);
  });

  test('a fridge bottle with no kind, or one unknown, is breast milk', () {
    expect(MilkKind.fromName(null), MilkKind.expressed);
    expect(MilkKind.fromName('oat'), MilkKind.expressed);
    expect(MilkKind.fromName('wholeMilk'), MilkKind.wholeMilk);
  });

  test('a feed stores its milk by name, and leaves it out when unknown', () {
    final at = DateTime(2026, 9, 25, 9);
    final whole = FeedingEvent(
      id: 'f',
      type: FeedingType.bottle,
      startTime: at,
      amountMl: 150,
      milk: MilkKind.wholeMilk,
    );
    expect(whole.toMap()['milk'], 'wholeMilk');

    final unknown = FeedingEvent(
      id: 'g',
      type: FeedingType.bottle,
      startTime: at,
      amountMl: 150,
    );
    expect(unknown.toMap().containsKey('milk'), isFalse);
  });
}
