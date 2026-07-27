import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pumping_event.dart';

/// Reads/writes pump sessions for one baby: `babies/{babyId}/pumps/{id}`.
/// [_uid] is the current caregiver, stamped onto writes (KAN-159).
class PumpingRepository {
  PumpingRepository(this._firestore, this._babyId, this._uid);

  final FirebaseFirestore _firestore;
  final String _babyId;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('babies').doc(_babyId).collection('pumps');

  Stream<List<PumpingEvent>> watchRecent({int limit = 50}) {
    return _col
        .orderBy('time', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(PumpingEvent.fromDoc).toList());
  }

  Stream<List<PumpingEvent>> watchForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _col
        .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('time', isLessThan: Timestamp.fromDate(end))
        .orderBy('time')
        .snapshots()
        .map((snap) => snap.docs.map(PumpingEvent.fromDoc).toList());
  }

  /// One-shot fetch of every pump session in [start, end), earliest first.
  /// Powers the insights trends (KAN-166) rather than a live stream.
  Future<List<PumpingEvent>> fetchRange(DateTime start, DateTime end) async {
    final snap = await _col
        .where('time', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('time', isLessThan: Timestamp.fromDate(end))
        .orderBy('time')
        .get();
    return snap.docs.map(PumpingEvent.fromDoc).toList();
  }

  Future<String> add(PumpingEvent event) async {
    final doc = await _col.add({
      ...event.toMap(),
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> update(PumpingEvent event) => _col.doc(event.id).update({
    ...event.toMap(),
    'updatedBy': _uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> delete(String id) => _col.doc(id).delete();
}
