import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/fridge/fridge_order.dart';
import '../models/fridge_bottle.dart';
import '../models/fridge_log_entry.dart';
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
/// Takes [EventRepository] rather than [TimelineRepository]. The shelf is a
/// list of what is there now, read whole, and "most recent 50" is not a
/// question anyone asks of it. What happened to it is kept beside it, in the
/// fridge's own history ([watchLog]).
class FridgeRepository extends EventRepository<FridgeBottle> {
  FridgeRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'bottles';

  @override
  String get timeField => 'filledAt';

  @override
  FridgeBottle fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      FridgeBottle.fromDoc(doc);

  /// What happened to the shelf: `babies/{babyId}/fridgeLog`.
  CollectionReference<Map<String, dynamic>> get _log =>
      firestore.collection('babies').doc(babyId).collection('fridgeLog');

  Map<String, dynamic> _logged(FridgeLogEntry entry) => {
    ...entry.toMap(),
    'createdBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _created(FridgeBottle bottle) => {
    ...bottle.toMap(),
    'createdBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
  };

  /// The fridge's history, newest first: the last [limit] things done to it.
  Stream<List<FridgeLogEntry>> watchLog({int limit = 100}) => _log
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [...s.docs.map(FridgeLogEntry.fromDoc).nonNulls]);

  /// Puts [event] on the shelf, and says so in the history.
  @override
  Future<String> add(FridgeBottle event) async {
    final doc = col.doc();
    final placed = FridgeBottle(
      id: doc.id,
      filledAt: event.filledAt,
      amountMl: event.amountMl,
      kind: event.kind,
      notes: event.notes,
      pumpId: event.pumpId,
      parts: event.parts,
    );
    await (firestore.batch()
          ..set(doc, _created(placed))
          ..set(
            _log.doc(),
            _logged(
              FridgeLogEntry.of(FridgeAction.added, placed, at: DateTime.now()),
            ),
          ))
        .commit();
    return doc.id;
  }

  /// Takes [bottle] off the shelf without its being fed. The history keeps
  /// it whole, so it can be put back.
  Future<void> remove(FridgeBottle bottle) =>
      _takeOff(bottle, FridgeAction.removed);

  /// Takes [bottle] off the shelf as it is fed.
  Future<void> finish(FridgeBottle bottle) =>
      _takeOff(bottle, FridgeAction.fed);

  Future<void> _takeOff(FridgeBottle bottle, FridgeAction why) =>
      (firestore.batch()
            ..delete(col.doc(bottle.id))
            ..set(
              _log.doc(),
              _logged(FridgeLogEntry.of(why, bottle, at: DateTime.now())),
            ))
          .commit();

  /// Puts a removed bottle back as it was, under its old id.
  Future<void> restore(FridgeLogEntry removed) {
    final bottle = removed.bottle;
    return (firestore.batch()
          ..set(col.doc(bottle.id), _created(bottle))
          ..set(
            _log.doc(),
            _logged(
              FridgeLogEntry.of(
                FridgeAction.restored,
                bottle,
                at: DateTime.now(),
              ),
            ),
          ))
        .commit();
  }

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
  ///
  /// What the two bottles become is [splitBottle]'s; this only writes it.
  Future<void> split(FridgeBottle bottle, double firstMl) {
    final fresh = col.doc();
    final (:kept, :sibling) = splitBottle(bottle, firstMl, siblingId: fresh.id);
    final batch = firestore.batch()
      ..set(fresh, {
        ...sibling.toMap(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..update(col.doc(bottle.id), {
        ...kept.toMap(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      })
      ..set(
        _log.doc(),
        _logged(
          FridgeLogEntry.of(
            FridgeAction.split,
            bottle,
            at: DateTime.now(),
            otherMl: sibling.amountMl,
          ),
        ),
      );
    return batch.commit();
  }

  /// Pours [pourMl] of [poured] into [kept] — all of it when null.
  ///
  /// [kept] becomes [combined] of the two. [poured] keeps what was left in
  /// it, or goes when it was poured out entirely. One batch, so no device
  /// ever sees the milk counted twice, or gone.
  ///
  /// What each bottle becomes is [combined] and [pouredRemainder]'s, each
  /// saying what happened in its notes; this only writes it.
  Future<void> combine(
    FridgeBottle kept,
    FridgeBottle poured, {
    double? pourMl,
  }) {
    final pour = pourMl ?? poured.amountMl;
    final batch = firestore.batch()
      ..set(
        _log.doc(),
        _logged(
          FridgeLogEntry.of(
            FridgeAction.combined,
            poured,
            at: DateTime.now(),
            otherMl: pour,
          ),
        ),
      )
      ..update(col.doc(kept.id), {
        ...combined(kept, poured, pourMl: pour).toMap(),
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    switch (pouredRemainder(poured, pour)) {
      case final left?:
        batch.update(col.doc(poured.id), {
          'amountMl': left.amountMl,
          'notes': left.notes,
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      case null:
        batch.delete(col.doc(poured.id));
    }
    return batch.commit();
  }
}
