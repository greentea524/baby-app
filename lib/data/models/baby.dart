import 'package:cloud_firestore/cloud_firestore.dart';

/// Biological sex, used for WHO growth percentiles (KAN-163). Optional so
/// existing profiles remain valid; percentiles need it set.
enum BabySex { male, female }

/// A baby profile. Stored at `users/{uid}/babies/{id}`.
class Baby {
  const Baby({
    required this.id,
    required this.name,
    required this.birthDate,
    this.sex,
  });

  final String id;
  final String name;
  final DateTime birthDate;
  final BabySex? sex;

  factory Baby.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final sexName = data['sex'] as String?;
    return Baby(
      id: doc.id,
      name: data['name'] as String,
      birthDate: (data['birthDate'] as Timestamp).toDate(),
      sex: sexName == null ? null : BabySex.values.asNameMap()[sexName],
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'birthDate': Timestamp.fromDate(birthDate),
    'sex': sex?.name,
  };

  Baby copyWith({String? name, DateTime? birthDate, BabySex? sex}) => Baby(
    id: id,
    name: name ?? this.name,
    birthDate: birthDate ?? this.birthDate,
    sex: sex ?? this.sex,
  );
}
