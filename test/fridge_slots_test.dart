import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/features/fridge/fridge_slots.dart';

/// Where each bottle stands: A, B, C, or Other.
void main() {
  final base = DateTime(2026, 10, 1, 6);

  FridgeBottle bottle(
    String id, {
    required int hour,
    FridgeSlot? slot,
    int? position,
  }) => FridgeBottle(
    id: id,
    filledAt: base.add(Duration(hours: hour)),
    amountMl: 100,
    slot: slot,
    position: position,
  );

  List<String> ids(Iterable<FridgeBottle> bs) => [for (final b in bs) b.id];

  test('a stored slot is kept, and an empty one stays empty', () {
    // A was finished. Nobody slides along.
    final layout = layoutShelf([
      bottle('b', hour: 1, slot: FridgeSlot.b),
      bottle('c', hour: 2, slot: FridgeSlot.c),
    ]);
    expect(layout.labelled.containsKey(FridgeSlot.a), isFalse);
    expect(layout.labelled[FridgeSlot.b]!.id, 'b');
    expect(layout.labelled[FridgeSlot.c]!.id, 'c');
    expect(layout.toSave, isEmpty);
    expect(layout.firstFree, FridgeSlot.a);
  });

  test('bottles with no slot fill the gaps, oldest first, then Other', () {
    final layout = layoutShelf([
      bottle('kept', hour: 0, slot: FridgeSlot.b),
      bottle('new3', hour: 5),
      bottle('new1', hour: 1),
      bottle('new2', hour: 3),
    ]);
    expect(layout.labelled[FridgeSlot.a]!.id, 'new1');
    expect(layout.labelled[FridgeSlot.b]!.id, 'kept');
    expect(layout.labelled[FridgeSlot.c]!.id, 'new2');
    expect(ids(layout.other), ['new3']);
    expect(layout.toSave, {
      'new1': FridgeSlot.a,
      'new2': FridgeSlot.c,
      'new3': FridgeSlot.other,
    });
  });

  test('a shelf that was arranged by hand keeps that order into A–C', () {
    final layout = layoutShelf([
      bottle('old', hour: 0, position: 2),
      bottle('mid', hour: 1, position: 0),
      bottle('new', hour: 2, position: 1),
    ]);
    expect(ids(layout.inOrder), ['mid', 'new', 'old']);
  });

  test('two bottles stored in one slot: the older keeps it', () {
    // Only two devices saving at once can do this.
    final layout = layoutShelf([
      bottle('late', hour: 4, slot: FridgeSlot.a),
      bottle('early', hour: 1, slot: FridgeSlot.a),
    ]);
    expect(layout.labelled[FridgeSlot.a]!.id, 'early');
    expect(ids(layout.other), ['late']);
    expect(layout.toSave, {'late': FridgeSlot.other});
  });

  test('Other is oldest first, and the order of reach is A, B, C, Other', () {
    final layout = layoutShelf([
      bottle('o2', hour: 9, slot: FridgeSlot.other),
      bottle('c', hour: 3, slot: FridgeSlot.c),
      bottle('o1', hour: 2, slot: FridgeSlot.other),
      bottle('a', hour: 8, slot: FridgeSlot.a),
    ]);
    expect(ids(layout.other), ['o1', 'o2']);
    expect(ids(layout.inOrder), ['a', 'c', 'o1', 'o2']);
    expect(layout.firstFree, FridgeSlot.b);
    expect(layout.count, 4);
  });

  test('a full set of letters sends the next bottle to Other', () {
    final layout = layoutShelf([
      bottle('a', hour: 1, slot: FridgeSlot.a),
      bottle('b', hour: 2, slot: FridgeSlot.b),
      bottle('c', hour: 3, slot: FridgeSlot.c),
    ]);
    expect(layout.firstFree, FridgeSlot.other);
  });

  test('says where a bottle is', () {
    final a = bottle('a', hour: 1, slot: FridgeSlot.a);
    final o = bottle('o', hour: 2, slot: FridgeSlot.other);
    final layout = layoutShelf([a, o]);
    expect(layout.slotOf(a), FridgeSlot.a);
    expect(layout.slotOf(o), FridgeSlot.other);
    expect(layout.slotOf(bottle('gone', hour: 3)), isNull);
  });

  test('the slot is stored by name, and only when known', () {
    expect(bottle('a', hour: 1, slot: FridgeSlot.c).toMap()['slot'], 'c');
    expect(bottle('a', hour: 1).toMap().containsKey('slot'), isFalse);
    expect(FridgeSlot.fromName('other'), FridgeSlot.other);
    expect(FridgeSlot.fromName(null), isNull);
    expect(FridgeSlot.fromName('z'), isNull);
  });
}
