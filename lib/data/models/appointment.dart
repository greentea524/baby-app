import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby_event.dart';

/// What kind of visit an appointment is (KAN-176). Display labels and icons
/// live in `AppointmentFormat` so the model stays free of Flutter imports.
enum AppointmentKind { checkup, vaccination, specialist, dental, other }

/// A scheduled visit, stored at `babies/{babyId}/appointments/{id}`.
///
/// The first forward-looking record in the app — everything else logs what
/// already happened.
class Appointment implements BabyEvent {
  const Appointment({
    required this.id,
    required this.at,
    this.kind = AppointmentKind.checkup,
    this.title,
    this.provider,
    this.location,
    this.notes,
    this.completedAt,
  });

  @override
  final String id;

  /// When the appointment is. Stored as an absolute instant; the UI renders
  /// it in the device's local time.
  final DateTime at;

  final AppointmentKind kind;

  /// Optional free-text name, e.g. "6-month well visit". Falls back to the
  /// kind's label when empty.
  final String? title;

  final String? provider;
  final String? location;
  final String? notes;

  /// Set once the visit has happened, so it reads as done rather than just
  /// being in the past.
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  /// Whether this is still ahead of [now].
  bool isUpcoming(DateTime now) => !at.isBefore(now);

  Appointment copyWith({
    DateTime? at,
    AppointmentKind? kind,
    String? title,
    String? provider,
    String? location,
    String? notes,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) => Appointment(
    id: id,
    at: at ?? this.at,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    provider: provider ?? this.provider,
    location: location ?? this.location,
    notes: notes ?? this.notes,
    // A plain `??` could never un-complete a visit, so clearing is explicit.
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
  );

  factory Appointment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Appointment(
      id: doc.id,
      at: (data['at'] as Timestamp).toDate(),
      kind:
          AppointmentKind.values.asNameMap()[data['kind'] as String?] ??
          AppointmentKind.checkup,
      title: data['title'] as String?,
      provider: data['provider'] as String?,
      location: data['location'] as String?,
      notes: data['notes'] as String?,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'at': Timestamp.fromDate(at),
    'kind': kind.name,
    'title': title,
    'provider': provider,
    'location': location,
    'notes': notes,
    'completedAt': completedAt == null
        ? null
        : Timestamp.fromDate(completedAt!),
  };
}
