import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
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
    BottleKind kind = BottleKind.expressed,
  }) => FridgeBottle(
    id: id,
    filledAt: base.add(Duration(hours: atHour)),
    amountMl: ml,
    position: position,
    kind: kind,
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

  group('what kind of bottle', () {
    test('the two are counted apart', () {
      // They do not keep the same way, so how much of each there is is a
      // different fact from how much there is.
      final totals = totalByKind([
        bottle('a', atHour: 1, ml: 90),
        bottle('b', atHour: 2, ml: 60, kind: BottleKind.formula),
        bottle('c', atHour: 3, ml: 30),
      ]);
      expect(totals[BottleKind.expressed], 120);
      expect(totals[BottleKind.formula], 60);
    });

    test('and a kind nothing is stored under is absent, not zero', () {
      // The summary line reads these keys, and "Formula 0 ml" is a line about
      // nothing.
      expect(totalByKind([bottle('a', atHour: 1, ml: 90)]).keys, [
        BottleKind.expressed,
      ]);
    });

    test('a stored kind reads back', () {
      expect(BottleKind.fromName('formula'), BottleKind.formula);
      expect(BottleKind.fromName('expressed'), BottleKind.expressed);
    });

    test('and anything else reads as expressed', () {
      // A bottle written before formula was a kind, and one written by a
      // version that knows something this one does not. Expressed is the
      // commoner kind and the one the shelf started life holding.
      expect(BottleKind.fromName(null), BottleKind.expressed);
      expect(BottleKind.fromName('oat milk'), BottleKind.expressed);
    });

    test('each says what its own timestamp means', () {
      // "Pumped 11:00" and "Made up 11:00" are different facts. A bottle that
      // claims the wrong one is worse than one that says neither.
      expect(BottleKind.expressed.filledLabel, 'Pumped');
      expect(BottleKind.formula.filledLabel, 'Made up');
    });

    test('and the two look different on a shelf', () {
      expect(BottleKind.formula.icon, isNot(BottleKind.expressed.icon));
      expect(BottleKind.formula.label, isNot(BottleKind.expressed.label));
    });
  });

  group('how full a bottle is', () {
    test('against the 120 ml the household\'s bottles hold', () {
      expect(bottleCapacityMl, 120);
      expect(fullness(120), 1.0);
      expect(fullness(90), 0.75);
      expect(fullness(60), 0.5);
      expect(fullness(0), 0.0);
    });

    test('full, not overflowing, past the top mark', () {
      // A reading over capacity is a bigger bottle, not a spill. The number
      // on the card stays exact.
      expect(fullness(150), 1.0);
    });
  });

  group('whether a pump session is already in a bottle', () {
    final pumped = DateTime(2026, 9, 25, 9, 5, 33);
    FridgeBottle filled(
      DateTime at, {
      BottleKind kind = BottleKind.expressed,
    }) => FridgeBottle(id: 'a', filledAt: at, amountMl: 90, kind: kind);

    test('a bottle filled after it is that milk', () {
      // Bottles are stamped when they go in the fridge, now, which is after
      // the session rather than at it.
      expect(isBottled(pumped, [filled(DateTime(2026, 9, 25, 9, 40))]), isTrue);
    });

    test('and so is one carrying its own time, as bottles once did', () {
      expect(isBottled(pumped, [filled(pumped)]), isTrue);
      // To the minute: a time picked by hand has no seconds.
      expect(isBottled(pumped, [filled(DateTime(2026, 9, 25, 9, 5))]), isTrue);
    });

    test('a bottle filled before it is not', () {
      expect(isBottled(pumped, [filled(DateTime(2026, 9, 25, 9, 4))]), isFalse);
    });

    test('nor one filled after the next session', () {
      // That bottle is the later session's milk.
      expect(
        isBottled(pumped, [
          filled(DateTime(2026, 9, 25, 12, 30)),
        ], nextPumpAt: DateTime(2026, 9, 25, 12)),
        isFalse,
      );
      expect(
        isBottled(pumped, [
          filled(DateTime(2026, 9, 25, 11, 30)),
        ], nextPumpAt: DateTime(2026, 9, 25, 12)),
        isTrue,
      );
    });

    test('and formula made up after it is not that milk', () {
      expect(
        isBottled(pumped, [
          filled(DateTime(2026, 9, 25, 9, 40), kind: BottleKind.formula),
        ]),
        isFalse,
      );
    });

    test('and an empty fridge holds nothing', () {
      expect(isBottled(pumped, const []), isFalse);
    });
  });

  group('the pump a new bottle takes its amount from', () {
    final session = PumpingEvent(
      id: 'p',
      time: DateTime(2026, 9, 25, 9, 5),
      amountMl: 110,
    );
    FeedingEvent feed(DateTime at, {FeedingType type = FeedingType.bottle}) =>
        FeedingEvent(id: 'f', type: type, startTime: at, amountMl: 110);

    test('is the last session, while nothing has happened to it', () {
      expect(unbottledPump(session, shelf: const [], feeds: const []), session);
    });

    test('but not once it is in a bottle', () {
      expect(
        unbottledPump(
          session,
          shelf: [
            FridgeBottle(
              id: 'a',
              filledAt: DateTime(2026, 9, 25, 9, 20),
              amountMl: 110,
            ),
          ],
          feeds: const [],
        ),
        isNull,
      );
    });

    test('nor once a bottle has been fed since', () {
      // Reported: the add sheet kept offering a session that had long since
      // been bottled and drunk. Finishing the bottle took it off the shelf,
      // and with it the only sign the session had been dealt with; the feed
      // it logged is the sign that stays.
      expect(
        unbottledPump(
          session,
          shelf: const [],
          feeds: [feed(DateTime(2026, 9, 25, 11))],
        ),
        isNull,
      );
    });

    test('though a feed from before it, or of solids, changes nothing', () {
      expect(
        unbottledPump(
          session,
          shelf: const [],
          feeds: [
            feed(DateTime(2026, 9, 25, 8)),
            feed(DateTime(2026, 9, 25, 11), type: FeedingType.solids),
          ],
        ),
        session,
      );
    });

    test('and there is none when nothing has been pumped', () {
      expect(unbottledPump(null, shelf: const [], feeds: const []), isNull);
    });
  });
}
