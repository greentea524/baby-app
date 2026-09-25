import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/fridge_bottle.dart';
import 'event_repository.dart';

/// What is standing in the fridge, for one baby:
/// `babies/{babyId}/bottles/{id}`.
///
/// `bottles`, not `fridge` — the collection is named for what is stored, the
/// way `pumps` is.
///
/// Takes [EventRepository] rather than [TimelineRepository]. A fridge has no
/// history to page through: it is a list of what is there now, read whole,
/// and "most recent 50" is not a question anyone asks of it.
class FridgeRepository extends EventRepository<FridgeBottle> {
  FridgeRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'bottles';

  @override
  String get timeField => 'filledAt';

  @override
  FridgeBottle fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      FridgeBottle.fromDoc(doc);

  /// Everything in the fridge, oldest first.
  ///
  /// Unlimited on purpose. The screen is an inventory of a physical shelf, so
  /// a bottle left off the end would be a bottle the caregiver goes looking
  /// for and cannot find; a fridge holds few enough that the cost is nothing.
  ///
  /// Ordered by age here and re-sorted in the client when the shelf has been
  /// arranged by hand. Firestore cannot order on a field that is null for
  /// some documents and set for others without dropping the nulls, and
  /// dropping them would hide exactly the bottles added since the last
  /// tidy-up.
  Stream<List<FridgeBottle>> watchAll() =>
      col.orderBy(timeField).snapshots().map(parse);

  /// Numbers the shelf to match [ordered], left to right.
  ///
  /// Every bottle in one batch, rather than only the one that moved. Positions
  /// have to stay a dense run for the next drag to land predictably, and a
  /// fridge is small enough that rewriting all of them is a single round trip.
  Future<void> saveOrder(List<FridgeBottle> ordered) {
    final batch = firestore.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(col.doc(ordered[i].id), {
        'position': i,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }

  /// Gives up the hand-arranged order and goes back to oldest first.
  Future<void> clearOrder(List<FridgeBottle> bottles) {
    final batch = firestore.batch();
    for (final b in bottles) {
      batch.update(col.doc(b.id), {
        'position': null,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }

  /// Splits [bottle] so that [firstMl] stays where it is and the rest becomes
  /// a second bottle beside it.
  ///
  /// The two halves keep the original's timestamp and kind: one pour became
  /// two containers, and the milk is neither younger nor a different thing for
  /// having been moved. They also add up — the amounts are not rounded on the
  /// way through, so a 155 ml bottle split in two is 78 and 77, never 80 and
  /// 75.
  ///
  /// [shelf] is the order on screen. Needed only when the shelf is arranged by
  /// hand, and then it is needed badly: the new bottle has to appear next to
  /// its sibling rather than at the far end, which means renumbering. The id
  /// is taken from Firestore locally rather than awaited, so the whole split
  /// is one atomic batch instead of an add followed by a reorder that could
  /// fail on its own.
  Future<void> split(
    FridgeBottle bottle,
    double firstMl, {
    required List<FridgeBottle> shelf,
  }) {
    final fresh = col.doc();
    final byHand = shelf.any((b) => b.position != null);

    final ordered = [...shelf];
    final at = ordered.indexWhere((b) => b.id == bottle.id);
    final sibling = FridgeBottle(
      id: fresh.id,
      filledAt: bottle.filledAt,
      amountMl: bottle.amountMl - firstMl,
      kind: bottle.kind,
      notes: bottle.notes,
    );
    ordered.insert(at + 1, sibling);

    final batch = firestore.batch();
    for (var i = 0; i < ordered.length; i++) {
      final b = ordered[i];
      // Null while the shelf is in age order, where copyWith leaves the
      // already-null position alone.
      final position = byHand ? i : null;
      if (b.id == fresh.id) {
        batch.set(fresh, {
          ...b.copyWith(position: position).toMap(),
          'createdBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (b.id == bottle.id) {
        batch.update(col.doc(b.id), {
          ...b.copyWith(amountMl: firstMl, position: position).toMap(),
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (byHand) {
        batch.update(col.doc(b.id), {
          'position': position,
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    return batch.commit();
  }
}
