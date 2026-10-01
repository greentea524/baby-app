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

  test('two filled at the same moment come out the same on every device', () {
    // Both halves of a split share a time. Whichever order a device
    // happened to receive them in, Other lists them the same way.
    final first = bottle('a-half', hour: 2, slot: FridgeSlot.other);
    final second = bottle('b-half', hour: 2, slot: FridgeSlot.other);
    expect(ids(layoutShelf([first, second]).other), ['a-half', 'b-half']);
    expect(ids(layoutShelf([second, first]).other), ['a-half', 'b-half']);
  });

  test('and a shared slot goes to the same one of them everywhere', () {
    final x = bottle('x', hour: 2, slot: FridgeSlot.a);
    final y = bottle('y', hour: 2, slot: FridgeSlot.a);
    for (final order in [
      [x, y],
      [y, x],
    ]) {
      final layout = layoutShelf(order);
      expect(layout.labelled[FridgeSlot.a]!.id, 'x');
      expect(layout.toSave, {'y': FridgeSlot.other});
    }
  });

  test('a letter two devices filled stays with the bottle there first', () {
    // Reported: logging a pump "overwrote" a bottle. The pumped bottle's
    // milk was older (it carries its pump time), and a shared letter used to
    // go to the older milk — so the bottle already there was pushed out.
    final there = FridgeBottle(
      id: 'there',
      filledAt: base.add(const Duration(hours: 5)),
      amountMl: 90,
      slot: FridgeSlot.a,
      slottedAt: base.add(const Duration(hours: 5)),
    );
    final pumped = FridgeBottle(
      id: 'pumped',
      filledAt: base.add(const Duration(hours: 1)),
      amountMl: 120,
      slot: FridgeSlot.a,
      slottedAt: base.add(const Duration(hours: 6)),
    );
    final layout = layoutShelf([pumped, there]);
    expect(layout.labelled[FridgeSlot.a]!.id, 'there');
    expect(ids(layout.other), ['pumped']);
    expect(layout.toSave, {'pumped': FridgeSlot.other});
  });

  test('a bottle placed before this was recorded counts as there first', () {
    final legacy = bottle('legacy', hour: 5, slot: FridgeSlot.b);
    final newer = FridgeBottle(
      id: 'newer',
      filledAt: base,
      amountMl: 60,
      slot: FridgeSlot.b,
      slottedAt: base.add(const Duration(hours: 9)),
    );
    expect(layoutShelf([newer, legacy]).labelled[FridgeSlot.b]!.id, 'legacy');
  });

  test('when a bottle took its slot is stored with it', () {
    final at = DateTime(2026, 10, 2, 9, 30);
    final map = FridgeBottle(
      id: 'x',
      filledAt: base,
      amountMl: 60,
      slot: FridgeSlot.c,
      slottedAt: at,
    ).toMap();
    expect(map['slot'], 'c');
    expect(map.containsKey('slottedAt'), isTrue);
    expect(bottle('y', hour: 1).toMap().containsKey('slottedAt'), isFalse);
  });

  test('which slots a bottle can be put in', () {
    final a = bottle('a', hour: 1, slot: FridgeSlot.a);
    final layout = layoutShelf([a]);
    // A new bottle: empty letters and Other, never a taken letter.
    expect(layout.canTake(FridgeSlot.a), isFalse);
    expect(layout.canTake(FridgeSlot.b), isTrue);
    expect(layout.canTake(FridgeSlot.other), isTrue);
    // The bottle already there: its own letter too.
    expect(layout.canTake(FridgeSlot.a, a), isTrue);
    expect(
      layout.canTake(FridgeSlot.a, bottle('b', hour: 2, slot: FridgeSlot.b)),
      isFalse,
    );
  });
}
