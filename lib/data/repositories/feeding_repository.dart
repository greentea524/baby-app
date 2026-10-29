import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/feeding_event.dart';
import 'event_repository.dart';

/// Feeding events for one baby: `babies/{babyId}/feedings/{eventId}`.
///
/// Everything it does lives in [TimelineRepository]; all that is particular
/// to feeds is the collection, the field the time is under, and how to read
/// one back.
class FeedingRepository extends TimelineRepository<FeedingEvent> {
  FeedingRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'feedings';

  @override
  String get timeField => 'startTime';

  @override
  FeedingEvent fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      FeedingEvent.fromDoc(doc);
}
