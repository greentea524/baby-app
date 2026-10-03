import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/fridge/fridge_order.dart';
import '../models/fridge_bottle.dart';
import 'event_repository.dart';

/// Whether the fridge on this device is in step with the server — see
/// [FridgeRepository.watchSync].
typedef FridgeSync = ({bool fromCache, bool pending});

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
  /// Oldest first, which is the order the shelf shows them in: the order
  /// milk should be used in.
  Stream<List<FridgeBottle>> watchAll() =>
      col.orderBy(timeField).snapshots().map(parse);

  /// Whether this device is in step with everyone else's fridge: showing
  /// what is only in its own cache, or holding changes not sent yet.
  ///
  /// The same query as [watchAll], so Firestore serves both from one
  /// listener; asked for metadata changes, so it says when a pending write
  /// has gone, not only when a bottle changes.
  Stream<FridgeSync> watchSync() => col
      .orderBy(timeField)
      .snapshots(includeMetadataChanges: true)
      .map(
        (s) => (
          fromCache: s.metadata.isFromCache,
          pending: s.metadata.hasPendingWrites,
        ),
      );

  /// Splits [bottle] so that [firstMl] stays where it is and the rest becomes
  /// a second bottle.
  ///
  /// The two halves keep the original's timestamp and kind: one pour became
  /// two containers, and the milk is neither younger nor a different thing for
  /// having been moved. They also add up — the amounts are not rounded on the
  /// way through, so a 155 ml bottle split in two is 78 and 77, never 80 and
  /// 75. Being the same age, they stand side by side on the shelf.
  ///
  /// The id is taken from Firestore locally rather than awaited, so the whole
  /// split is one atomic batch.
  Future<void> split(FridgeBottle bottle, double firstMl) {
    final fresh = col.doc();
    final sibling = FridgeBottle(
      id: fresh.id,
      filledAt: bottle.filledAt,
      amountMl: bottle.amountMl - firstMl,
      kind: bottle.kind,
      notes: bottle.notes,
    );
    final batch = firestore.batch()
      ..set(fresh, {
        ...sibling.toMap(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..update(col.doc(bottle.id), {
        ...bottle.copyWith(amountMl: firstMl).toMap(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    return batch.commit();
  }

  /// Pours [poured] into [kept]: [kept] becomes [combined] of the two, and
  /// [poured] goes.
  ///
  /// One batch, so no device ever sees the milk counted twice, or gone.
  Future<void> combine(FridgeBottle kept, FridgeBottle poured) {
    final batch = firestore.batch()
      ..update(col.doc(kept.id), {
        ...combined(kept, poured).toMap(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      })
      ..delete(col.doc(poured.id));
    return batch.commit();
  }
}
