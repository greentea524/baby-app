import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/medication_event.dart';
import 'event_repository.dart';

/// Doses of medicine for one baby: `babies/{babyId}/meds/{eventId}`.
class MedicationRepository extends TimelineRepository<MedicationEvent> {
  MedicationRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'meds';

  @override
  String get timeField => 'time';

  @override
  MedicationEvent fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      MedicationEvent.fromDoc(doc);
}
