import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/baby.dart';

/// Reads/writes baby profiles under the signed-in user's document:
/// `users/{uid}/babies/{babyId}`. Scoping every collection under the uid
/// keeps Firestore security rules trivial (a user only touches their tree)
/// and sets up multi-caregiver sharing (KAN-134) later.
class BabiesRepository {
  BabiesRepository(this._firestore, this._uid);

  final FirebaseFirestore _firestore;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('users').doc(_uid).collection('babies');

  Stream<List<Baby>> watchBabies() {
    return _col
        .orderBy('birthDate')
        .snapshots()
        .map((snap) => snap.docs.map(Baby.fromDoc).toList());
  }

  Future<String> addBaby({
    required String name,
    required DateTime birthDate,
  }) async {
    final doc = await _col.add({
      'name': name,
      'birthDate': Timestamp.fromDate(birthDate),
    });
    return doc.id;
  }

  Future<void> updateBaby(Baby baby) => _col.doc(baby.id).update(baby.toMap());

  Future<void> deleteBaby(String id) => _col.doc(id).delete();
}
