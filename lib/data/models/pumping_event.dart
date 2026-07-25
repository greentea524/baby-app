import 'package:cloud_firestore/cloud_firestore.dart';

import 'feeding_event.dart' show BreastSide;

/// A breast-pump session. Stored at `babies/{babyId}/pumps/{id}`. Kept
/// separate from feeding (KAN-145): pumping tracks milk *supply*, not the
/// baby's intake, so it shouldn't skew feeding totals/intervals.
class PumpingEvent {
  const PumpingEvent({
    required this.id,
    required this.time,
    this.durationMinutes,
    this.amountMl,
    this.side,
    this.notes,
  });

  final String id;
  final DateTime time;
  final int? durationMinutes;
  final double? amountMl;
  final BreastSide? side;
  final String? notes;

  factory PumpingEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return PumpingEvent(
      id: doc.id,
      time: (data['time'] as Timestamp).toDate(),
      durationMinutes: data['durationMinutes'] as int?,
      amountMl: (data['amountMl'] as num?)?.toDouble(),
      side: data['side'] == null
          ? null
          : BreastSide.values.byName(data['side'] as String),
      notes: data['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'time': Timestamp.fromDate(time),
    'durationMinutes': durationMinutes,
    'amountMl': amountMl,
    'side': side?.name,
    'notes': notes,
  };
}
