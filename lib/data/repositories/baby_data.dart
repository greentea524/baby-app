import 'package:cloud_firestore/cloud_firestore.dart';

/// Everything stored under one baby, and how to count or destroy it (#28).
///
/// Firestore does not delete a document's subcollections along with it, so
/// `babies/{id}.delete()` — which is what the app did — left every feed,
/// change, measurement, pump, appointment and invite exactly where it was.
/// Worse than orphaned: every subcollection rule is gated on
/// `isMember(babyId)`, which reads the baby document, so once that document
/// is gone the rules deny everyone and the data cannot be reached again from
/// any client. Verified against the emulator; see `rules-tests/`.
///
/// **Hence the one rule this class exists to enforce: children first, the
/// baby last.** Delete the parent first and the delete becomes impossible to
/// finish.
class BabyData {
  BabyData(this._firestore);

  final FirebaseFirestore _firestore;

  /// The subcollections a baby owns, named rather than discovered.
  ///
  /// The same five events `firestore.rules` names one at a time (#22), plus
  /// invites. A wildcard sweep would be the same mistake in the other
  /// direction: something nobody meant to delete, deleted anyway.
  static const collections = <String>[
    'feedings',
    'diapers',
    'growth',
    'pumps',
    'appointments',
    'invites',
  ];

  /// What each collection is called when counted out loud, singular then
  /// plural. Invites are left out — a pending invitation is not a record of
  /// anything that happened, and listing it beside 900 feeds reads as noise.
  static const _spoken = <String, (String, String)>{
    'feedings': ('feed', 'feeds'),
    'diapers': ('diaper change', 'diaper changes'),
    'growth': ('growth measurement', 'growth measurements'),
    'pumps': ('pumping session', 'pumping sessions'),
    'appointments': ('appointment', 'appointments'),
  };

  /// A batch is capped at 500 writes; this leaves room to be wrong about
  /// that without discovering it mid-delete.
  static const _batchSize = 400;

  DocumentReference<Map<String, dynamic>> _baby(String id) =>
      _firestore.collection('babies').doc(id);

  /// How many documents each collection holds, skipping the empty ones.
  ///
  /// Counted so the confirmation can say what is about to go rather than
  /// asking whether you are sure. `count()` is an aggregation — it does not
  /// read the documents, so this stays cheap on a baby with thousands.
  Future<Map<String, int>> countAll(String babyId) async {
    final counts = <String, int>{};
    for (final name in collections) {
      final snap = await _baby(babyId).collection(name).count().get();
      final n = snap.count ?? 0;
      if (n > 0) counts[name] = n;
    }
    return counts;
  }

  /// "1,284 feeds, 903 diaper changes and 12 growth measurements".
  ///
  /// The whole point of the sentence is that it is specific. "This cannot be
  /// undone" is true of every destructive dialog ever written and reads as
  /// boilerplate; a number is what makes someone stop.
  static String describe(Map<String, int> counts) {
    final parts = [
      for (final entry in _spoken.entries)
        if ((counts[entry.key] ?? 0) > 0)
          '${counts[entry.key]} '
              '${counts[entry.key] == 1 ? entry.value.$1 : entry.value.$2}',
    ];
    if (parts.isEmpty) return 'no logged entries';
    if (parts.length == 1) return parts.single;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  /// Deletes every document under [babyId], then the baby itself.
  ///
  /// [onProgress] receives the running total, for a screen that would
  /// otherwise sit still through a few thousand deletes.
  ///
  /// Interrupting this is safe and resumable, which is the reason for the
  /// order: the baby document is the last thing to go, so until it does the
  /// rules still admit the caller and running it again picks up where it
  /// stopped. There is no state in between that anyone is locked out of.
  Future<void> deleteAll(String babyId, {void Function(int)? onProgress}) async {
    var done = 0;
    for (final name in collections) {
      done = await _drain(_baby(babyId).collection(name), done, onProgress);
    }
    await _baby(babyId).delete();
  }

  Future<int> _drain(
    CollectionReference<Map<String, dynamic>> col,
    int done,
    void Function(int)? onProgress,
  ) async {
    var total = done;
    while (true) {
      // From the server, not the cache. Offline persistence would happily
      // answer from a stale local copy, and "deleted everything" measured
      // against a cache is not a claim worth making. Offline this throws,
      // which is the right outcome: the batch below would not complete
      // either, it would simply hang until the device reconnected (#21).
      final snap = await col
          .limit(_batchSize)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) return total;

      final batch = col.firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      total += snap.docs.length;
      onProgress?.call(total);

      // A short page means the collection is done. Saves one round trip per
      // collection, which on six collections is most of the round trips.
      if (snap.docs.length < _batchSize) return total;
    }
  }
}
