import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/fridge/fridge_slots.dart';
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

  /// Stores places worked out on screen — see [ShelfLayout.toSave].
  Future<void> place(Map<String, FridgeSlot> slots) {
    final batch = firestore.batch();
    for (final MapEntry(:key, :value) in slots.entries) {
      batch.update(col.doc(key), _slot(value));
    }
    return batch.commit();
  }

  /// Puts a new [bottle] in [slot].
  ///
  /// A letter that is taken is taken over: the bottle already in it moves to
  /// Other, in the same batch, so two bottles never share a letter. The id is
  /// made locally, as for a split, so it is one write rather than two.
  Future<void> addTo(
    FridgeBottle bottle,
    FridgeSlot slot, {
    required ShelfLayout layout,
  }) {
    final fresh = col.doc();
    final batch = firestore.batch()
      ..set(fresh, {
        ...bottle.copyWith(slot: slot).toMap(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    if (layout.labelled[slot] case final occupant? when slot.isLabelled) {
      batch.update(col.doc(occupant.id), _slot(FridgeSlot.other));
    }
    return batch.commit();
  }

  /// Saves [bottle], moving it to [slot].
  ///
  /// Moving onto a taken letter swaps the two: the bottle that was there goes
  /// to where this one came from. One batch, so the shelf is never seen with
  /// both in the same place.
  Future<void> saveIn(
    FridgeBottle bottle,
    FridgeSlot slot, {
    required ShelfLayout layout,
  }) {
    final from = layout.slotOf(bottle) ?? FridgeSlot.other;
    final batch = firestore.batch()
      ..update(col.doc(bottle.id), {
        ...bottle.copyWith(slot: slot).toMap(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    if (layout.labelled[slot] case final occupant?
        when slot.isLabelled && occupant.id != bottle.id) {
      batch.update(col.doc(occupant.id), _slot(from));
    }
    return batch.commit();
  }

  /// Moves [bottle] to [slot] and nothing else — a drag on the shelf.
  Future<void> moveTo(
    FridgeBottle bottle,
    FridgeSlot slot, {
    required ShelfLayout layout,
  }) {
    final from = layout.slotOf(bottle) ?? FridgeSlot.other;
    if (from == slot) return Future.value();
    final batch = firestore.batch()..update(col.doc(bottle.id), _slot(slot));
    if (layout.labelled[slot] case final occupant? when slot.isLabelled) {
      batch.update(col.doc(occupant.id), _slot(from));
    }
    return batch.commit();
  }

  Map<String, Object> _slot(FridgeSlot slot) => {
    'slot': slot.name,
    'updatedBy': uid,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Splits [bottle] so that [firstMl] stays where it is and the rest becomes
  /// a second bottle.
  ///
  /// The two halves keep the original's timestamp and kind: one pour became
  /// two containers, and the milk is neither younger nor a different thing for
  /// having been moved. They also add up — the amounts are not rounded on the
  /// way through, so a 155 ml bottle split in two is 78 and 77, never 80 and
  /// 75.
  ///
  /// The original keeps its slot; the new half goes in the first empty
  /// letter, or Other. The id is taken from Firestore locally rather than
  /// awaited, so the whole split is one atomic batch.
  Future<void> split(
    FridgeBottle bottle,
    double firstMl, {
    required ShelfLayout layout,
  }) {
    final fresh = col.doc();
    final sibling = FridgeBottle(
      id: fresh.id,
      filledAt: bottle.filledAt,
      amountMl: bottle.amountMl - firstMl,
      kind: bottle.kind,
      notes: bottle.notes,
      slot: layout.firstFree,
    );
    final batch = firestore.batch()
      ..set(fresh, {
        ...sibling.toMap(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..update(col.doc(bottle.id), {
        ...bottle
            .copyWith(
              amountMl: firstMl,
              slot: layout.slotOf(bottle) ?? FridgeSlot.other,
            )
            .toMap(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    return batch.commit();
  }
}
