import 'package:cloud_firestore/cloud_firestore.dart';

enum FeedingType { breast, bottle, solids }

enum BreastSide { left, right, both }

/// A feeding event. Stored at `users/{uid}/babies/{babyId}/feedings/{id}`.
/// Full CRUD lands with the Feeding Logging epic (KAN-130); this defines
/// the schema the rest of the app scopes against.
class FeedingEvent {
  const FeedingEvent({
    required this.id,
    required this.type,
    required this.startTime,
    this.durationMinutes,
    this.amountMl,
    this.side,
    this.notes,
  });

  final String id;
  final FeedingType type;
  final DateTime startTime;
  final int? durationMinutes;
  final double? amountMl;
  final BreastSide? side;
  final String? notes;

  factory FeedingEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return FeedingEvent(
      id: doc.id,
      type: FeedingType.values.byName(data['type'] as String),
      startTime: (data['startTime'] as Timestamp).toDate(),
      durationMinutes: data['durationMinutes'] as int?,
      amountMl: (data['amountMl'] as num?)?.toDouble(),
      side: data['side'] == null
          ? null
          : BreastSide.values.byName(data['side'] as String),
      notes: data['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'startTime': Timestamp.fromDate(startTime),
        'durationMinutes': durationMinutes,
        'amountMl': amountMl,
        'side': side?.name,
        'notes': notes,
      };
}
