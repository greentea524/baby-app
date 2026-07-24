import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/growth_measurement.dart';

/// Reads/writes growth measurements for one baby:
/// `users/{uid}/babies/{babyId}/growth/{id}`.
class GrowthRepository {
  GrowthRepository(this._firestore, this._uid, this._babyId);

  final FirebaseFirestore _firestore;
  final String _uid;
  final String _babyId;

  CollectionReference<Map<String, dynamic>> get _col => _firestore
      .collection('users')
      .doc(_uid)
      .collection('babies')
      .doc(_babyId)
      .collection('growth');

  /// Oldest first, so charts read left-to-right in time order.
  Stream<List<GrowthMeasurement>> watchAll() {
    return _col
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map(GrowthMeasurement.fromDoc).toList());
  }

  Future<String> add(GrowthMeasurement m) async {
    final doc = await _col.add(m.toMap());
    return doc.id;
  }

  Future<void> update(GrowthMeasurement m) => _col.doc(m.id).update(m.toMap());

  Future<void> delete(String id) => _col.doc(id).delete();
}
