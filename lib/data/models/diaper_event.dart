import 'package:cloud_firestore/cloud_firestore.dart';

enum DiaperType { wet, dirty, both }

/// A diaper change. Stored at `users/{uid}/babies/{babyId}/diapers/{id}`.
/// Full CRUD lands with the Diaper Change Logging epic (KAN-131).
class DiaperEvent {
  const DiaperEvent({
    required this.id,
    required this.type,
    required this.time,
    this.notes,
  });

  final String id;
  final DiaperType type;
  final DateTime time;
  final String? notes;

  factory DiaperEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return DiaperEvent(
      id: doc.id,
      type: DiaperType.values.byName(data['type'] as String),
      time: (data['time'] as Timestamp).toDate(),
      notes: data['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'time': Timestamp.fromDate(time),
    'notes': notes,
  };
}
