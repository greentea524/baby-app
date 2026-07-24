import 'package:cloud_firestore/cloud_firestore.dart';

/// A growth data point. Stored at
/// `users/{uid}/babies/{babyId}/growth/{id}`. Any subset of the three
/// metrics may be present (a visit might record only weight, say).
class GrowthMeasurement {
  const GrowthMeasurement({
    required this.id,
    required this.date,
    this.weightKg,
    this.heightCm,
    this.headCm,
  });

  final String id;
  final DateTime date;
  final double? weightKg;
  final double? heightCm;
  final double? headCm;

  bool get hasAny => weightKg != null || heightCm != null || headCm != null;

  factory GrowthMeasurement.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return GrowthMeasurement(
      id: doc.id,
      date: (data['date'] as Timestamp).toDate(),
      weightKg: (data['weightKg'] as num?)?.toDouble(),
      heightCm: (data['heightCm'] as num?)?.toDouble(),
      headCm: (data['headCm'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'weightKg': weightKg,
    'heightCm': heightCm,
    'headCm': headCm,
  };
}
