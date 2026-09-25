/// How the bottles line up on screen, left to right.
///
/// Two orders, and which one applies is read off the bottles themselves.
/// Oldest first by default, because that is the order milk should be used in
/// and the order a shelf gets stocked in. Once someone has dragged a bottle,
/// every bottle carries a position and the shelf shows exactly what they
/// arranged — the point of dragging is to match a fridge that is *not* in age
/// order, so age has to stop deciding the moment it is overruled.
library;

import '../../data/models/fridge_bottle.dart';

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

/// [shelf] with the bottle at [from] moved to sit at [to].
///
/// Takes the indices `ReorderableListView.onReorderItem` reports, which are
/// already counted against the list with the dragged bottle lifted out — so
/// this is a plain remove and insert, with none of the off-by-one the older
/// `onReorder` callback needed.
List<FridgeBottle> reordered(List<FridgeBottle> shelf, int from, int to) {
  final ordered = [...shelf];
  ordered.insert(to, ordered.removeAt(from));
  return ordered;
}

/// What is in the fridge altogether.
double totalMl(List<FridgeBottle> bottles) =>
    bottles.fold(0, (sum, b) => sum + b.amountMl);

/// How much of each kind, for the kinds that are actually there.
///
/// Absent rather than zero for a kind the fridge holds none of: the summary
/// line reads the keys, and "0 ml of formula" is a line about nothing.
Map<BottleKind, double> totalByKind(List<FridgeBottle> bottles) {
  final totals = <BottleKind, double>{};
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

/// Whether milk pumped at [pumpedAt] is already standing on [shelf].
///
/// A bottle made from a pump session carries that session's time, which is
/// how it is recognised: the add sheet opens on the last session, and once
/// that session is in the fridge, opening on it again would offer to bottle
/// the same milk twice.
///
/// Matched to the minute rather than exactly. The session is stamped to the
/// second when it is logged, and a bottle whose time was re-picked lands on
/// the minute — still the same milk.
///
/// Breast milk only: formula made up in the same minute is not that
/// session's milk.
bool isOnShelf(DateTime pumpedAt, List<FridgeBottle> shelf) {
  DateTime minute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);
  final target = minute(pumpedAt);
  return shelf.any(
    (b) => b.kind == BottleKind.expressed && minute(b.filledAt) == target,
  );
}
