import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/growth_measurement.dart';
import 'event_repository.dart';

/// Growth measurements for one baby: `babies/{babyId}/growth/{eventId}`.
///
/// Takes [EventRepository] rather than [TimelineRepository]: measurements are
/// read oldest-first and all at once, because a growth chart is a line
/// through a whole history rather than a list of what just happened.
class GrowthRepository extends EventRepository<GrowthMeasurement> {
  GrowthRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'growth';

  @override
  String get timeField => 'date';

  @override
  GrowthMeasurement fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      GrowthMeasurement.fromDoc(doc);

  /// Oldest first, so charts read left-to-right in time order.
  Stream<List<GrowthMeasurement>> watchAll() =>
      col.orderBy(timeField).snapshots().map(parse);

  /// One-shot fetch of all measurements, earliest first (export, KAN-137).
  Future<List<GrowthMeasurement>> fetchAll() async =>
      parse(await col.orderBy(timeField).get());
}
