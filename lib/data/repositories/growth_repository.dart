import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/growth_measurement.dart';

/// Reads/writes growth measurements for one baby:
/// `babies/{babyId}/growth/{id}`. [_uid] is the current caregiver, stamped
/// onto writes for attribution (KAN-159).
class GrowthRepository {
  GrowthRepository(this._firestore, this._babyId, this._uid);

  final FirebaseFirestore _firestore;
  final String _babyId;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('babies').doc(_babyId).collection('growth');

  /// Oldest first, so charts read left-to-right in time order.
  Stream<List<GrowthMeasurement>> watchAll() {
    return _col
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map(GrowthMeasurement.fromDoc).toList());
  }

  /// One-shot fetch of all measurements, earliest first (export, KAN-137).
  Future<List<GrowthMeasurement>> fetchAll() async {
    final snap = await _col.orderBy('date').get();
    return snap.docs.map(GrowthMeasurement.fromDoc).toList();
  }

  Future<String> add(GrowthMeasurement m) async {
    final doc = await _col.add({
      ...m.toMap(),
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> update(GrowthMeasurement m) => _col.doc(m.id).update({
    ...m.toMap(),
    'updatedBy': _uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> delete(String id) => _col.doc(id).delete();
}
