import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appointment.dart';
import 'event_repository.dart';

/// Scheduled visits for one baby: `babies/{babyId}/appointments/{eventId}`.
class AppointmentsRepository extends EventRepository<Appointment> {
  AppointmentsRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'appointments';

  @override
  String get timeField => 'at';

  @override
  Appointment fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Appointment.fromDoc(doc);

  /// Every appointment in date order, earliest first.
  ///
  /// Deliberately *not* split server-side into upcoming/past with a
  /// `where('at' >= now)`: that bakes "now" in when the stream is created, so
  /// an appointment that comes due while the app is open would sit in
  /// "upcoming" forever. Splitting client-side re-evaluates on every build,
  /// and the document count here is tiny — a child has dozens of visits, not
  /// thousands.
  Stream<List<Appointment>> watchAll({int limit = 200}) =>
      col.orderBy(timeField).limit(limit).snapshots().map(parse);
}
