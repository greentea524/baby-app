import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/data/models/fridge_bottle.dart';
import 'package:baby_app/features/fridge/fridge_order.dart';

/// Which order the bottles stand in, and the sums over them.
void main() {
  final base = DateTime(2026, 9, 25, 6);

  FridgeBottle bottle(
    String id, {
    required int atHour,
    double ml = 100,
    MilkKind kind = MilkKind.expressed,
  }) => FridgeBottle(
    id: id,
    filledAt: base.add(Duration(hours: atHour)),
    amountMl: ml,
    kind: kind,
  );

  List<String> idsOf(List<FridgeBottle> shelf) =>
      shelf.map((b) => b.id).toList();

  group('the shelf', () {
    test('the oldest is leftmost', () {
      // The end you take from, and the order the screen exists to suggest.
      final shelf = shelfOrder([
        bottle('c', atHour: 9),
        bottle('a', atHour: 1),
        bottle('b', atHour: 5),
      ]);
      expect(idsOf(shelf), ['a', 'b', 'c']);
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

  group('combining two', () {
    test('holds the exact sum', () {
      // Never rounded: 30 and 100 make 130, and halves make a whole.
      final into = combined(
        bottle('a', atHour: 1, ml: 30),
        bottle('b', atHour: 5, ml: 100),
      );
      expect(into.amountMl, 130);
      expect(
        combined(
          bottle('a', atHour: 1, ml: 77.5),
          bottle('b', atHour: 2, ml: 77.5),
        ).amountMl,
        155,
      );
    });

    test('keeps the older time, whichever bottle it was on', () {
      // Milk is as old as its oldest part.
      final older = bottle('old', atHour: 1);
      final newer = bottle('new', atHour: 9);
      expect(combined(newer, older).filledAt, older.filledAt);
      expect(combined(older, newer).filledAt, older.filledAt);
      // And stays the bottle it was poured into.
      expect(combined(newer, older).id, 'new');
    });

    test('keeps both notes, skipping blank ones, and says what happened', () {
      FridgeBottle noted(String id, String? notes, {double ml = 50}) =>
          FridgeBottle(id: id, filledAt: base, amountMl: ml, notes: notes);
      expect(
        combined(noted('a', 'left side'), noted('b', 'for daycare')).notes,
        'left side · for daycare · Combined 50 + 50 ml',
      );
      expect(
        combined(noted('a', '  '), noted('b', 'for daycare')).notes,
        'for daycare · Combined 50 + 50 ml',
      );
      // Notes or not, the bottle remembers why it holds what it does.
      expect(
        combined(noted('a', null, ml: 60), noted('b', null, ml: 100)).notes,
        'Combined 60 + 100 ml',
      );
      // A partial pour records what was poured, not what the other held.
      expect(
        combined(
          noted('a', null, ml: 60),
          noted('b', null, ml: 100),
          pourMl: 40,
        ).notes,
        'Combined 60 + 40 ml',
      );
    });

    test('pours only what is asked, at the older time still', () {
      final older = bottle('old', atHour: 1, ml: 100);
      final kept = bottle('new', atHour: 9, ml: 80);
      final into = combined(kept, older, pourMl: 40);
      expect(into.amountMl, 120);
      expect(into.filledAt, older.filledAt);
    });

    test('and by default, what fills this one up', () {
      // 80 ml has room for 40 of a 120 ml bottle.
      expect(
        defaultPourMl(
          bottle('k', atHour: 1, ml: 80),
          bottle('p', atHour: 2, ml: 100),
        ),
        40,
      );
      // All of it when it fits.
      expect(
        defaultPourMl(
          bottle('k', atHour: 1, ml: 80),
          bottle('p', atHour: 2, ml: 30),
        ),
        30,
      );
      // All of it when this one is full already: there is nothing to top up.
      expect(
        defaultPourMl(
          bottle('k', atHour: 1, ml: 130),
          bottle('p', atHour: 2, ml: 30),
        ),
        30,
      );
    });

    test('the pour moves 5 ml at a time, and can always take it all', () {
      expect(pourStops(20), [5, 10, 15, 20]);
      // Not a whole number of steps: the last stop is all of it.
      expect(pourStops(23), [5, 10, 15, 20, 23]);
      // Less than a step: only the whole of it.
      expect(pourStops(4), [4]);
    });

    test('a split moves in the same steps, a step each side at least', () {
      expect(splitStops(20), [5, 10, 15]);
      // The second bottle takes the odd millilitres.
      expect(splitStops(23), [5, 10, 15]);
      expect(splitStops(10), [5]);
      expect(splitStops(9), isEmpty);
    });

    test('and starts on the step nearest half', () {
      expect(defaultSplitMl(100), 50);
      expect(defaultSplitMl(123), 60);
      // A tie goes to the lower.
      expect(defaultSplitMl(125), 60);
      expect(defaultSplitMl(10), 5);
      expect(defaultSplitMl(9), isNull);
    });

    test('and starts on a stop, never past full', () {
      // 77 ml has room for 43; the stop below that is 40.
      expect(
        defaultPourMl(
          bottle('k', atHour: 1, ml: 77),
          bottle('p', atHour: 2, ml: 100),
        ),
        40,
      );
    });

    test('only of the same kind, and not with itself', () {
      final milk = bottle('a', atHour: 1);
      expect(canCombine(milk, bottle('b', atHour: 2)), isTrue);
      expect(
        canCombine(milk, bottle('f', atHour: 2, kind: MilkKind.formula)),
        isFalse,
      );
      expect(canCombine(milk, milk), isFalse);
    });
  });

  group('what kind of bottle', () {
    test('the two are counted apart', () {
      // They do not keep the same way, so how much of each there is is a
      // different fact from how much there is.
      final totals = totalByKind([
        bottle('a', atHour: 1, ml: 90),
        bottle('b', atHour: 2, ml: 60, kind: MilkKind.formula),
        bottle('c', atHour: 3, ml: 30),
      ]);
      expect(totals[MilkKind.expressed], 120);
      expect(totals[MilkKind.formula], 60);
    });

    test('and a kind nothing is stored under is absent, not zero', () {
      // The summary line reads these keys, and "Formula 0 ml" is a line about
      // nothing.
      expect(totalByKind([bottle('a', atHour: 1, ml: 90)]).keys, [
        MilkKind.expressed,
      ]);
    });

    test('a stored kind reads back', () {
      expect(MilkKind.fromName('formula'), MilkKind.formula);
      expect(MilkKind.fromName('expressed'), MilkKind.expressed);
    });

    test('and anything else reads as expressed', () {
      // A bottle written before formula was a kind, and one written by a
      // version that knows something this one does not. Expressed is the
      // commoner kind and the one the shelf started life holding.
      expect(MilkKind.fromName(null), MilkKind.expressed);
      expect(MilkKind.fromName('oat milk'), MilkKind.expressed);
    });

    test('each says what its own timestamp means', () {
      // "Pumped 11:00" and "Made up 11:00" are different facts. A bottle that
      // claims the wrong one is worse than one that says neither.
      expect(MilkKind.expressed.filledLabel, 'Pumped');
      expect(MilkKind.formula.filledLabel, 'Made up');
    });

    test('and the two look different on a shelf', () {
      expect(MilkKind.formula.icon, isNot(MilkKind.expressed.icon));
      expect(MilkKind.formula.label, isNot(MilkKind.expressed.label));
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
    FridgeBottle filled(DateTime at, {MilkKind kind = MilkKind.expressed}) =>
        FridgeBottle(id: 'a', filledAt: at, amountMl: 90, kind: kind);

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
          filled(DateTime(2026, 9, 25, 9, 40), kind: MilkKind.formula),
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

  group('how old a bottle is', () {
    final now = DateTime(2026, 10, 2, 12);
    BottleAge ageAt(Duration d) => BottleAge.of(now.subtract(d), now);

    test('fresh for its first two days', () {
      expect(ageAt(Duration.zero), BottleAge.fresh);
      expect(ageAt(const Duration(hours: 47, minutes: 59)), BottleAge.fresh);
    });

    test('yellow from two days', () {
      expect(ageAt(const Duration(hours: 48)), BottleAge.aging);
      expect(ageAt(const Duration(hours: 71, minutes: 59)), BottleAge.aging);
    });

    test('red from three', () {
      expect(ageAt(const Duration(hours: 72)), BottleAge.old);
      expect(ageAt(const Duration(days: 9)), BottleAge.old);
    });
  });

  group('how long ago, in hours', () {
    final now = DateTime(2026, 10, 2, 12);
    String ago(Duration d) => hoursAgo(now.subtract(d), now);

    test('hours and minutes past a day, never "1 day ago"', () {
      expect(ago(const Duration(hours: 33, minutes: 13)), '33 hr 13 min ago');
      expect(ago(const Duration(hours: 24)), '24 hr ago');
      expect(ago(const Duration(hours: 80)), '80 hr ago');
    });

    test('and as before within the day', () {
      expect(ago(const Duration(hours: 15, minutes: 33)), '15 hr 33 min ago');
      expect(ago(const Duration(minutes: 20)), '20 min ago');
      expect(ago(const Duration(seconds: 30)), 'just now');
    });
  });

  group('drink by', () {
    test('what is left of the time to it, full to empty', () {
      final filled = DateTime(2026, 10, 1, 6);
      expect(drinkByRemaining(filled, filled), 1);
      expect(drinkByRemaining(filled, DateTime(2026, 10, 3, 6)), 0.5);
      expect(drinkByRemaining(filled, DateTime(2026, 10, 5, 6)), 0);
      // Empty, not negative, once past.
      expect(drinkByRemaining(filled, DateTime(2026, 10, 9)), 0);
    });

    test('and where on it the card turns yellow, then red', () {
      final filled = DateTime(2026, 10, 1, 6);
      expect(drinkByRemainingAt(BottleAge.agingAfter, filled), 0.5);
      expect(drinkByRemainingAt(BottleAge.oldAfter, filled), 0.25);
    });

    test('four calendar days on, at the same time', () {
      expect(drinkBy(DateTime(2026, 10, 1, 5, 6)), DateTime(2026, 10, 5, 5, 6));
      // Across a month end.
      expect(
        drinkBy(DateTime(2026, 9, 29, 22, 0)),
        DateTime(2026, 10, 3, 22, 0),
      );
    });

    test('past it from that moment on', () {
      final filled = DateTime(2026, 10, 1, 5, 6);
      expect(isPastDrinkBy(filled, DateTime(2026, 10, 5, 5, 5)), isFalse);
      expect(isPastDrinkBy(filled, DateTime(2026, 10, 5, 5, 6)), isTrue);
    });

    test('says today and tomorrow, otherwise the date', () {
      final now = DateTime(2026, 10, 3, 9);
      expect(
        drinkByText(DateTime(2026, 10, 3, 20), now, '8 PM'),
        'Today, 8 PM',
      );
      expect(
        drinkByText(DateTime(2026, 10, 4, 6), now, '6 AM'),
        'Tomorrow, 6 AM',
      );
      expect(drinkByText(DateTime(2026, 10, 5, 6), now, '6 AM'), 'Oct 5, 6 AM');
    });
  });

  group('what happened to a bottle, in its notes', () {
    test('a split says where both halves came from', () {
      expect(
        splitEntry(totalMl: 123, firstMl: 60),
        'Split from 123 ml into 60 + 63 ml',
      );
      // Half millilitres stay as they are rather than rounding off the sum.
      expect(
        splitEntry(totalMl: 125, firstMl: 62.5),
        'Split from 125 ml into 62.5 + 62.5 ml',
      );
    });

    test('a bottle poured from says how much went', () {
      expect(
        pouredOutEntry(pouredMl: 40, fromMl: 100),
        'Poured 40 of 100 ml into another bottle',
      );
    });

    test('goes after what was written, which stays first', () {
      expect(withHistory(null, 'Combined 60 + 40 ml'), 'Combined 60 + 40 ml');
      expect(withHistory('  ', 'Combined 60 + 40 ml'), 'Combined 60 + 40 ml');
      expect(
        withHistory('Vitamin D', 'Combined 60 + 40 ml'),
        'Vitamin D · Combined 60 + 40 ml',
      );
      expect(
        withHistory('Vitamin D · Combined 60 + 40 ml', 'Split from 100 ml'),
        'Vitamin D · Combined 60 + 40 ml · Split from 100 ml',
      );
    });

    test('and never past what the rules allow, losing the oldest first', () {
      var notes = 'Vitamin D';
      for (var i = 0; i < 100; i++) {
        notes = withHistory(notes, 'Combined $i + 5 ml');
        expect(notes.length, lessThanOrEqualTo(bottleNotesMax));
      }
      expect(notes, startsWith('Vitamin D · '));
      expect(notes, endsWith('Combined 99 + 5 ml'));
      expect(notes, isNot(contains('Combined 0 + 5 ml')));
    });

    test('and leaves a note already at the limit as it is', () {
      final full = 'x' * bottleNotesMax;
      expect(withHistory(full, 'Combined 60 + 40 ml'), full);
    });
  });

  group('what a split and a pour leave behind', () {
    final filled = DateTime(2026, 10, 9, 8);
    final bottle = FridgeBottle(
      id: 'a',
      filledAt: filled,
      amountMl: 123,
      kind: MilkKind.formula,
      notes: 'Vitamin D',
    );

    test('a split leaves two bottles that say where they came from', () {
      final (:kept, :sibling) = splitBottle(bottle, 60, siblingId: 'b');
      expect(kept.id, 'a');
      expect(kept.amountMl, 60);
      expect(sibling.id, 'b');
      expect(sibling.amountMl, 63);
      // Same age and kind: one pour, two containers.
      expect(sibling.filledAt, filled);
      expect(sibling.kind, MilkKind.formula);
      const note = 'Vitamin D · Split from 123 ml into 60 + 63 ml';
      expect(kept.notes, note);
      expect(sibling.notes, note);
    });

    test('a bottle poured from keeps the rest, and says how much went', () {
      final left = pouredRemainder(bottle, 40)!;
      expect(left.id, 'a');
      expect(left.amountMl, 83);
      expect(left.filledAt, filled);
      expect(left.notes, 'Vitamin D · Poured 40 of 123 ml into another bottle');
    });

    test('and is gone when it was poured out entirely', () {
      expect(pouredRemainder(bottle, 123), isNull);
    });
  });
}
