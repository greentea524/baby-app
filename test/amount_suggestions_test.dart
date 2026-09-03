import 'package:baby_app/data/models/feeding_event.dart';
import 'package:baby_app/data/models/pumping_event.dart';
import 'package:baby_app/features/feeding/amount_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

/// One-tap bottle amounts, drawn from what this baby is actually fed (#31).
void main() {
  final base = DateTime(2026, 8, 30, 6);
  var seq = 0;

  FeedingEvent bottle(double? ml, {int atHour = 0, bool snack = false}) =>
      FeedingEvent(
        id: 'f${seq++}',
        type: FeedingType.bottle,
        startTime: base.add(Duration(hours: atHour)),
        amountMl: ml,
        isSnack: snack,
      );

  FeedingEvent other(FeedingType type, {int atHour = 0}) => FeedingEvent(
    id: 'f${seq++}',
    type: type,
    startTime: base.add(Duration(hours: atHour)),
    amountMl: 999,
  );

  PumpingEvent pump(double? ml, {required int atHour}) => PumpingEvent(
    id: 'p${seq++}',
    time: base.add(Duration(hours: atHour)),
    amountMl: ml,
  );

  List<double> mlOf(List<AmountSuggestion> s) =>
      s.map((e) => e.millilitres).toList();

  group('from past bottles', () {
    test('nothing logged suggests nothing', () {
      // Rather than a ladder this household never poured.
      expect(suggestedAmounts(feeds: const [], pumps: const []), isEmpty);
    });

    test('groups amounts that are one habit typed three ways', () {
      final feeds = [
        bottle(118),
        bottle(120, atHour: 1),
        bottle(122, atHour: 2),
      ];
      expect(mlOf(suggestedAmounts(feeds: feeds, pumps: const [])), [120]);
    });

    test('a value on the boundary goes up, and stays its own amount', () {
      // Any binning has to break the midpoint somewhere: 122 falls back to
      // 120, 123 goes up to 125. Pinned so the choice is visible rather than
      // surprising.
      final feeds = [bottle(122), bottle(123, atHour: 1)];
      expect(mlOf(suggestedAmounts(feeds: feeds, pumps: const [])), [120, 125]);
    });

    test('keeps the fives a household actually pours', () {
      // The reason the bins are five wide. At ten, every one of these moves
      // to a number nobody measured.
      final feeds = [bottle(105), bottle(75, atHour: 1), bottle(45, atHour: 2)];
      expect(mlOf(suggestedAmounts(feeds: feeds, pumps: const [])), [
        45,
        75,
        105,
      ]);
    });

    test('offers the most often poured first', () {
      final feeds = [
        for (var i = 0; i < 5; i++) bottle(120, atHour: i),
        for (var i = 5; i < 8; i++) bottle(90, atHour: i),
        bottle(150, atHour: 8),
      ];
      // Ranked 120, 90, 150 by how often each was poured — then shown
      // smallest first, so the row reads as a ladder.
      final picked = suggestedAmounts(feeds: feeds, pumps: const []);
      expect(mlOf(picked), [90, 120, 150]);
    });

    test('breaks a tie towards the more recent', () {
      // One each, and one more than fits. A rhythm that is changing should
      // move the chips rather than be outvoted by history, so the 30 poured
      // first is the one that drops.
      final feeds = [
        bottle(30, atHour: 0),
        bottle(60, atHour: 1),
        bottle(90, atHour: 2),
        bottle(120, atHour: 3),
        bottle(150, atHour: 4),
        bottle(180, atHour: 5),
      ];
      expect(mlOf(suggestedAmounts(feeds: feeds, pumps: const [])), [
        60,
        90,
        120,
        150,
        180,
      ]);
    });

    test('handles unsorted input', () {
      final feeds = [
        bottle(150, atHour: 4),
        bottle(30, atHour: 0),
        bottle(120, atHour: 3),
        bottle(180, atHour: 5),
        bottle(60, atHour: 1),
        bottle(90, atHour: 2),
      ];
      expect(mlOf(suggestedAmounts(feeds: feeds, pumps: const [])), [
        60,
        90,
        120,
        150,
        180,
      ]);
    });

    test('leaves snacks out, so a top-up cannot drag the ladder down', () {
      final feeds = [
        bottle(120, atHour: 0),
        for (var i = 1; i < 6; i++) bottle(20, atHour: i, snack: true),
      ];
      expect(mlOf(suggestedAmounts(feeds: feeds, pumps: const [])), [120]);
    });

    test('ignores feeds that carry no bottle volume', () {
      final feeds = [
        bottle(120),
        bottle(null, atHour: 1),
        other(FeedingType.breast, atHour: 2),
        other(FeedingType.solids, atHour: 3),
      ];
      expect(mlOf(suggestedAmounts(feeds: feeds, pumps: const [])), [120]);
    });

    test('drops an amount that rounds away to nothing', () {
      // A 2 ml entry snaps to 0, and a chip reading 0 is worse than one chip
      // fewer.
      final feeds = [bottle(2), bottle(120, atHour: 1)];
      expect(mlOf(suggestedAmounts(feeds: feeds, pumps: const [])), [120]);
    });

    test('shows fewer chips rather than padding to max', () {
      expect(
        suggestedAmounts(feeds: [bottle(120)], pumps: const []),
        hasLength(1),
      );
    });

    test('offers five by default', () {
      final feeds = [
        for (var i = 0; i < 8; i++) bottle(30.0 * (i + 1), atHour: i),
      ];
      expect(suggestedAmounts(feeds: feeds, pumps: const []), hasLength(5));
    });

    test('honours max', () {
      final feeds = [
        bottle(60, atHour: 0),
        bottle(90, atHour: 1),
        bottle(120, atHour: 2),
      ];
      expect(
        suggestedAmounts(feeds: feeds, pumps: const [], max: 2),
        hasLength(2),
      );
      expect(suggestedAmounts(feeds: feeds, pumps: const [], max: 0), isEmpty);
    });
  });

  group('from the last pump', () {
    test('keeps its place against a wall of bottles', () {
      // The reserved slot earning its keep: one pump session would lose every
      // frequency contest, and it is the only source that knows what is
      // actually in the bottle.
      final feeds = [for (var i = 0; i < 40; i++) bottle(120, atHour: i)];
      final picked = suggestedAmounts(
        feeds: feeds,
        pumps: [pump(130, atHour: 41)],
      );
      expect(mlOf(picked), [120, 130]);
      expect(
        picked.singleWhere((s) => s.millilitres == 130).source,
        AmountSource.pump,
      );
    });

    test('is offered at the amount actually pumped', () {
      // Reported: a 105 ml session came back as a 110 ml chip. The pump slot
      // is the one number that is a measurement rather than a habit, so
      // moving it offers milk that was never in the bottle.
      final picked = suggestedAmounts(
        feeds: const [],
        pumps: [pump(105, atHour: 1)],
      );
      expect(mlOf(picked), [105]);
    });

    test('is dropped once a bottle is logged after it', () {
      // Milk pumped at seven and given at nine is not what you are holding.
      final picked = suggestedAmounts(
        feeds: [bottle(120, atHour: 3)],
        pumps: [pump(130, atHour: 1)],
      );
      expect(mlOf(picked), [120]);
    });

    test('carries the first bottle when there is no history at all', () {
      final picked = suggestedAmounts(
        feeds: const [],
        pumps: [pump(130, atHour: 1)],
      );
      expect(mlOf(picked), [130]);
      expect(picked.single.source, AmountSource.pump);
    });

    test('takes the latest session, not the biggest', () {
      final picked = suggestedAmounts(
        feeds: const [],
        pumps: [pump(200, atHour: 1), pump(90, atHour: 5)],
      );
      expect(mlOf(picked), [90]);
    });

    test('skips sessions logged without an amount', () {
      final picked = suggestedAmounts(
        feeds: const [],
        pumps: [pump(130, atHour: 1), pump(null, atHour: 5)],
      );
      expect(mlOf(picked), [130]);
    });

    test('shows one chip when it lands on an amount already offered', () {
      final feeds = [for (var i = 0; i < 4; i++) bottle(120, atHour: i)];
      final picked = suggestedAmounts(
        feeds: feeds,
        pumps: [pump(122, atHour: 5)],
      );
      expect(mlOf(picked), [120]);
      expect(
        picked.single.source,
        AmountSource.pump,
        reason: 'the fresher fact',
      );
    });

    test('no pumps means the bottles fill the row', () {
      final feeds = [
        bottle(60, atHour: 0),
        bottle(90, atHour: 1),
        bottle(120, atHour: 2),
      ];
      final picked = suggestedAmounts(feeds: feeds, pumps: const []);
      expect(picked.every((s) => s.source == AmountSource.bottle), isTrue);
    });
  });
}
