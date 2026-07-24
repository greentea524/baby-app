import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/feeding_event.dart';

/// Reads/writes feeding events for one baby:
/// `users/{uid}/babies/{babyId}/feedings/{eventId}`.
class FeedingRepository {
  FeedingRepository(this._firestore, this._uid, this._babyId);

  final FirebaseFirestore _firestore;
  final String _uid;
  final String _babyId;

  CollectionReference<Map<String, dynamic>> get _col => _firestore
      .collection('users')
      .doc(_uid)
      .collection('babies')
      .doc(_babyId)
      .collection('feedings');

  /// Most recent feedings first. [limit] keeps the home/history views cheap.
  Stream<List<FeedingEvent>> watchRecent({int limit = 50}) {
    return _col
        .orderBy('startTime', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(FeedingEvent.fromDoc).toList());
  }

  Future<String> add(FeedingEvent event) async {
    final doc = await _col.add(event.toMap());
    return doc.id;
  }

  Future<void> update(FeedingEvent event) =>
      _col.doc(event.id).update(event.toMap());

  Future<void> delete(String id) => _col.doc(id).delete();
}
