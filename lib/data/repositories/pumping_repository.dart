import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pumping_event.dart';
import 'event_repository.dart';

/// Pump sessions for one baby: `babies/{babyId}/pumps/{eventId}`.
///
/// `pumps`, not `pumping` — the collection is named for what is stored.
class PumpingRepository extends TimelineRepository<PumpingEvent> {
  PumpingRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'pumps';

  @override
  String get timeField => 'time';

  @override
  PumpingEvent fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      PumpingEvent.fromDoc(doc);
}
