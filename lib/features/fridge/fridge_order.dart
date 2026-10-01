/// Sums and helpers for the fridge, and the order the shelf had before it
/// had slots.
///
/// That order — oldest first, or as arranged by hand once someone dragged a
/// bottle — now only decides where a bottle without a slot is first placed:
/// see `layoutShelf`. Bottles stored with a slot stay in it.
library;

import '../../data/models/feeding_event.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/models/pumping_event.dart';

/// Whether the shelf has been arranged by hand.
///
/// One positioned bottle is enough. Reordering numbers the whole shelf in a
/// single write, so a half-numbered shelf only exists if a write was
/// interrupted — and reading that as arranged is the safer of the two
/// guesses, since it keeps the part someone did arrange rather than throwing
/// it away.
bool isArrangedByHand(List<FridgeBottle> bottles) =>
    bottles.any((b) => b.position != null);

/// The bottles in shelf order: leftmost first.
///
/// Stable in both modes, so a rebuild never reshuffles two bottles that
/// compare equal. Ties break on id, which is arbitrary but fixed — a shelf
/// that reordered itself while being looked at would be unusable.
List<FridgeBottle> shelfOrder(List<FridgeBottle> bottles) {
  final ordered = [...bottles];
  if (isArrangedByHand(bottles)) {
    ordered.sort((a, b) {
      final ap = a.position;
      final bp = b.position;
      // An unpositioned bottle among positioned ones was added after the
      // shelf was arranged. It goes on the end, which is where a new bottle
      // lands in a fridge nobody has re-tidied.
      if (ap == null && bp == null) return a.id.compareTo(b.id);
      if (ap == null) return 1;
      if (bp == null) return -1;
      final byPosition = ap.compareTo(bp);
      return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
    });
    return ordered;
  }

  ordered.sort((a, b) {
    final byAge = a.filledAt.compareTo(b.filledAt);
    return byAge != 0 ? byAge : a.id.compareTo(b.id);
  });
  return ordered;
}

/// What is in the fridge altogether.
double totalMl(List<FridgeBottle> bottles) =>
    bottles.fold(0, (sum, b) => sum + b.amountMl);

/// How much of each kind, for the kinds that are actually there.
///
/// Absent rather than zero for a kind the fridge holds none of: the summary
/// line reads the keys, and "0 ml of formula" is a line about nothing.
Map<MilkKind, double> totalByKind(List<FridgeBottle> bottles) {
  final totals = <MilkKind, double>{};
  for (final b in bottles) {
    totals[b.kind] = (totals[b.kind] ?? 0) + b.amountMl;
  }
  return totals;
}

/// How much one bottle holds, full to the top mark.
///
/// One number, here, because it is one fact about the household's bottles
/// rather than about any bottle in particular. When the baby moves up to the
/// next size of bottle, this is the line that changes.
const double bottleCapacityMl = 120;

/// How full [amountMl] leaves a bottle, from 0 to 1.
///
/// Clamped at full rather than drawn spilling over. A reading over capacity
/// is a bottle bigger than this one, not an overflowing one, and the amount
/// written beside the drawing is exact either way — the drawing is for the
/// glance, the number is for the record.
double fullness(double amountMl) =>
    (amountMl / bottleCapacityMl).clamp(0.0, 1.0);

/// Whether milk pumped at [pumpedAt] has gone into a bottle on [shelf].
///
/// Read off the times: a breast-milk bottle filled at or after the session,
/// and before the next one, is that session's milk. A bottle used to carry
/// its session's own time, and was matched on it; it is now stamped when it
/// goes in the fridge, which is after the session, so the match is a window
/// rather than a moment. Bottles from before the change carry the session's
/// time and still land in it.
///
/// [nextPumpAt] closes the window. Without it, for the latest session, any
/// later bottle counts — there is no later milk it could be.
///
/// To the minute, since a time picked by hand has no seconds. Breast milk
/// only: formula made up after a session is not that session's milk.
bool isBottled(
  DateTime pumpedAt,
  List<FridgeBottle> shelf, {
  DateTime? nextPumpAt,
}) {
  DateTime minute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);
  final from = minute(pumpedAt);
  final until = nextPumpAt == null ? null : minute(nextPumpAt);
  return shelf.any((b) {
    if (b.kind != MilkKind.expressed) return false;
    final at = minute(b.filledAt);
    return !at.isBefore(from) && (until == null || at.isBefore(until));
  });
}

/// The last pump session, while its milk is still to be accounted for:
/// neither bottled nor given as a feed since.
///
/// What a new fridge bottle's amount is filled in from. Both tests, because
/// either way the milk is gone: into a bottle already on the shelf, or into
/// the baby — and a finished fridge bottle is logged as a feed, so that one
/// is caught here too, where the shelf no longer shows it.
PumpingEvent? unbottledPump(
  PumpingEvent? last, {
  required List<FridgeBottle> shelf,
  required List<FeedingEvent> feeds,
}) {
  if (last == null || isBottled(last.time, shelf)) return null;
  final fedSince = feeds.any(
    (f) => f.type == FeedingType.bottle && f.startTime.isAfter(last.time),
  );
  return fedSince ? null : last;
}

/// How long a bottle has been in the fridge, in the three steps the shelf
/// colours it by.
enum BottleAge {
  /// Under two days.
  fresh,

  /// Two days or more: yellow, use it soon.
  aging,

  /// Three days or more: red.
  old;

  /// Two days, measured from when the bottle was filled — pumped, made up or
  /// poured — not from when it went in the fridge, because it is the milk's
  /// age that matters.
  static const agingAfter = Duration(days: 2);
  static const oldAfter = Duration(days: 3);

  static BottleAge of(DateTime filledAt, DateTime now) {
    final age = now.difference(filledAt);
    if (age >= oldAfter) return old;
    if (age >= agingAfter) return aging;
    return fresh;
  }
}
