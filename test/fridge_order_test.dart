import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/features/fridge/fridge_order.dart';

/// Which order the bottles stand in, and what overrules what.
void main() {
  final base = DateTime(2026, 9, 25, 6);

  FridgeBottle bottle(
    String id, {
    required int atHour,
    double ml = 100,
    int? position,
  }) => FridgeBottle(
    id: id,
    pumpedAt: base.add(Duration(hours: atHour)),
    amountMl: ml,
    position: position,
  );

  List<String> idsOf(List<FridgeBottle> shelf) =>
      shelf.map((b) => b.id).toList();

  group('by default', () {
    test('the oldest is leftmost', () {
      // The end you take from, and the order the screen exists to suggest.
      final shelf = shelfOrder([
        bottle('c', atHour: 9),
        bottle('a', atHour: 1),
        bottle('b', atHour: 5),
      ]);
      expect(idsOf(shelf), ['a', 'b', 'c']);
    });

    test('and the shelf is not arranged by hand', () {
      expect(isArrangedByHand([bottle('a', atHour: 1)]), isFalse);
    });

    test('two pumped at the same moment keep a fixed order', () {
      // A split makes exactly this: two bottles sharing a timestamp. Without
      // a tie-break they could swap places on any rebuild, which on a screen
      // you are reading against a physical shelf is unusable.
      final first = shelfOrder([
        bottle('y', atHour: 3),
        bottle('x', atHour: 3),
      ]);
      final again = shelfOrder([
        bottle('x', atHour: 3),
        bottle('y', atHour: 3),
      ]);
      expect(idsOf(first), idsOf(again));
    });
  });

  group('once arranged by hand', () {
    test('position decides, not age', () {
      // The whole point of dragging: the fridge is not in age order, and the
      // screen has to show what is actually there.
      final shelf = shelfOrder([
        bottle('old', atHour: 1, position: 2),
        bottle('new', atHour: 9, position: 0),
        bottle('mid', atHour: 5, position: 1),
      ]);
      expect(idsOf(shelf), ['new', 'mid', 'old']);
    });

    test('one positioned bottle is enough to count as arranged', () {
      expect(
        isArrangedByHand([
          bottle('a', atHour: 1),
          bottle('b', atHour: 2, position: 0),
        ]),
        isTrue,
      );
    });

    test('a bottle added since goes on the end', () {
      // Where a new bottle lands in a fridge nobody has re-tidied. It has no
      // position, and guessing one from its age would move milk the caregiver
      // put somewhere specific.
      final shelf = shelfOrder([
        bottle('fresh', atHour: 9),
        bottle('left', atHour: 5, position: 0),
        bottle('right', atHour: 1, position: 1),
      ]);
      expect(idsOf(shelf), ['left', 'right', 'fresh']);
    });
  });

  group('moving one', () {
    final shelf = [
      bottle('a', atHour: 1),
      bottle('b', atHour: 2),
      bottle('c', atHour: 3),
    ];

    test('rightwards', () {
      // The indices onReorderItem reports are already counted with the
      // dragged bottle lifted out, so this is a plain remove and insert.
      expect(idsOf(reordered(shelf, 0, 2)), ['b', 'c', 'a']);
    });

    test('leftwards', () {
      expect(idsOf(reordered(shelf, 2, 0)), ['c', 'a', 'b']);
    });

    test('nowhere', () {
      expect(idsOf(reordered(shelf, 1, 1)), ['a', 'b', 'c']);
    });

    test('without disturbing the list it was given', () {
      reordered(shelf, 0, 2);
      expect(idsOf(shelf), ['a', 'b', 'c']);
    });
  });

  test('the total is what is in the fridge', () {
    expect(
      totalMl([bottle('a', atHour: 1, ml: 90), bottle('b', atHour: 2, ml: 65)]),
      155,
    );
    expect(totalMl(const []), 0);
  });
}
