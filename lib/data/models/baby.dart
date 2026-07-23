import 'package:cloud_firestore/cloud_firestore.dart';

/// A baby profile. Stored at `users/{uid}/babies/{id}`.
class Baby {
  const Baby({required this.id, required this.name, required this.birthDate});

  final String id;
  final String name;
  final DateTime birthDate;

  factory Baby.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Baby(
      id: doc.id,
      name: data['name'] as String,
      birthDate: (data['birthDate'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'birthDate': Timestamp.fromDate(birthDate),
  };

  Baby copyWith({String? name, DateTime? birthDate}) => Baby(
    id: id,
    name: name ?? this.name,
    birthDate: birthDate ?? this.birthDate,
  );
}
