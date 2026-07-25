import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/feeding_event.dart';

/// Reads/writes feeding events for one baby:
/// `babies/{babyId}/feedings/{eventId}`. [_uid] is the current caregiver,
/// stamped onto writes for attribution (KAN-159).
class FeedingRepository {
  FeedingRepository(this._firestore, this._babyId, this._uid);

  final FirebaseFirestore _firestore;
  final String _babyId;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('babies').doc(_babyId).collection('feedings');

  /// Most recent feedings first. [limit] keeps the home/history views cheap.
  Stream<List<FeedingEvent>> watchRecent({int limit = 50}) {
    return _col
        .orderBy('startTime', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(FeedingEvent.fromDoc).toList());
  }

  /// All feedings on the local calendar [day], earliest first. Powers the
  /// daily timeline (KAN-132).
  Stream<List<FeedingEvent>> watchForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _col
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime')
        .snapshots()
        .map((snap) => snap.docs.map(FeedingEvent.fromDoc).toList());
  }

  /// One-shot fetch of every feeding in [start, end), earliest first.
  /// Used by export (KAN-137) rather than a live stream.
  Future<List<FeedingEvent>> fetchRange(DateTime start, DateTime end) async {
    final snap = await _col
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime')
        .get();
    return snap.docs.map(FeedingEvent.fromDoc).toList();
  }

  Future<String> add(FeedingEvent event) async {
    final doc = await _col.add({
      ...event.toMap(),
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> update(FeedingEvent event) => _col.doc(event.id).update({
    ...event.toMap(),
    'updatedBy': _uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> delete(String id) => _col.doc(id).delete();
}
