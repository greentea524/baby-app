import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/diaper_event.dart';

/// Reads/writes diaper changes for one baby:
/// `users/{uid}/babies/{babyId}/diapers/{eventId}`.
class DiaperRepository {
  DiaperRepository(this._firestore, this._uid, this._babyId);

  final FirebaseFirestore _firestore;
  final String _uid;
  final String _babyId;

  CollectionReference<Map<String, dynamic>> get _col => _firestore
      .collection('users')
      .doc(_uid)
      .collection('babies')
      .doc(_babyId)
      .collection('diapers');

  /// Most recent changes first.
  Stream<List<DiaperEvent>> watchRecent({int limit = 50}) {
    return _col
        .orderBy('time', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(DiaperEvent.fromDoc).toList());
  }

  /// All diaper changes on the local calendar [day], earliest first.
  Stream<List<DiaperEvent>> watchForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _col
        .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('time', isLessThan: Timestamp.fromDate(end))
        .orderBy('time')
        .snapshots()
        .map((snap) => snap.docs.map(DiaperEvent.fromDoc).toList());
  }

  /// One-shot fetch of every diaper change in [start, end), earliest first.
  Future<List<DiaperEvent>> fetchRange(DateTime start, DateTime end) async {
    final snap = await _col
        .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('time', isLessThan: Timestamp.fromDate(end))
        .orderBy('time')
        .get();
    return snap.docs.map(DiaperEvent.fromDoc).toList();
  }

  Future<String> add(DiaperEvent event) async {
    final doc = await _col.add(event.toMap());
    return doc.id;
  }

  Future<void> update(DiaperEvent event) =>
      _col.doc(event.id).update(event.toMap());

  Future<void> delete(String id) => _col.doc(id).delete();
}
