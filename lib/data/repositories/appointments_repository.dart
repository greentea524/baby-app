import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appointment.dart';

/// Reads/writes scheduled visits for one baby:
/// `babies/{babyId}/appointments/{id}`. [_uid] is the current caregiver,
/// stamped onto writes for attribution (KAN-159).
class AppointmentsRepository {
  AppointmentsRepository(this._firestore, this._babyId, this._uid);

  final FirebaseFirestore _firestore;
  final String _babyId;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('babies').doc(_babyId).collection('appointments');

  /// Every appointment in date order, earliest first.
  ///
  /// Deliberately *not* split server-side into upcoming/past with a
  /// `where('at' >= now)`: that bakes "now" in when the stream is created, so
  /// an appointment that comes due while the app is open would sit in
  /// "upcoming" forever. Splitting client-side re-evaluates on every build,
  /// and the document count here is tiny — a child has dozens of visits, not
  /// thousands.
  Stream<List<Appointment>> watchAll({int limit = 200}) {
    return _col
        .orderBy('at')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Appointment.fromDoc).toList());
  }

  Future<String> add(Appointment appointment) async {
    final doc = await _col.add({
      ...appointment.toMap(),
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> update(Appointment appointment) =>
      _col.doc(appointment.id).update({
        ...appointment.toMap(),
        'updatedBy': _uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> delete(String id) => _col.doc(id).delete();
}
