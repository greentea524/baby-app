import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/diaper_event.dart';
import 'event_repository.dart';

/// Diaper changes for one baby: `babies/{babyId}/diapers/{eventId}`.
class DiaperRepository extends TimelineRepository<DiaperEvent> {
  DiaperRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'diapers';

  @override
  String get timeField => 'time';

  @override
  DiaperEvent fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      DiaperEvent.fromDoc(doc);
}
