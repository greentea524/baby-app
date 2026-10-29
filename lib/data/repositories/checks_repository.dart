import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/daily_check.dart';
import 'event_repository.dart';

/// The daily checklist's ticks for one baby: `babies/{babyId}/checks/{id}`.
class ChecksRepository extends TimelineRepository<DailyCheck> {
  ChecksRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'checks';

  @override
  String get timeField => 'time';

  @override
  DailyCheck fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      DailyCheck.fromDoc(doc);
}
