import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/care_stay.dart';
import 'event_repository.dart';

/// Drop-offs and pick-ups for one baby: `babies/{babyId}/stays/{id}`.
class StaysRepository extends TimelineRepository<CareStay> {
  StaysRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'stays';

  @override
  String get timeField => 'droppedAt';

  @override
  CareStay fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CareStay.fromDoc(doc);

  /// Marks the stay picked up at [at], or not picked up after all with null.
  ///
  /// Only that field: the stay's other fields — above all how far its
  /// automatic feeds have got — may have moved on since it was read.
  Future<void> setPickedUp(String id, DateTime? at) => col.doc(id).update({
    'pickedUpAt': at == null ? null : Timestamp.fromDate(at),
    'updatedBy': uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
