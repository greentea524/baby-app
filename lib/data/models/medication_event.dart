import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby_event.dart';

/// What a dose is measured in. Stored by [name]; the Firestore rules accept
/// exactly these.
enum DoseUnit {
  ml('ml', 'ml'),
  mg('mg', 'mg'),
  drops('drop', 'drops'),
  tablet('tablet', 'tablets'),
  puff('puff', 'puffs');

  const DoseUnit(this.singular, this.plural);

  final String singular;
  final String plural;

  /// "2.5 ml", "1 tablet", "3 drops".
  String amount(double dose) {
    final n = dose == dose.roundToDouble()
        ? dose.toInt().toString()
        : dose.toString();
    return '$n ${dose == 1 ? singular : plural}';
  }

  static DoseUnit? fromName(String? name) => values.asNameMap()[name];
}

/// One dose of medicine given. Stored at `babies/{babyId}/meds/{id}`.
///
/// What was given, how much, and when — a record, never a suggestion. The
/// app does not know any medicine or any dose; it writes down what the
/// caregiver gave.
class MedicationEvent implements BabyEvent {
  const MedicationEvent({
    required this.id,
    required this.time,
    required this.name,
    this.dose,
    this.unit,
    this.notes,
    this.createdBy,
    this.byName,
    this.waitHours,
  });

  @override
  final String id;
  final DateTime time;

  /// As typed: "Tylenol", "Gripe water".
  final String name;

  final double? dose;
  final DoseUnit? unit;
  final String? notes;

  /// Who logged it, by account. Written by the repository on create.
  final String? createdBy;

  /// What to call whoever logged it, taken from their account when they did.
  /// The app keeps no directory of caregivers' names, and "who gave the last
  /// dose" is the question two caregivers sharing a baby most need answered.
  final String? byName;

  /// How long to wait after this dose before the next of the same medicine,
  /// as the caregiver set it from the label or their doctor — never filled
  /// in by the app. Null for no wait.
  ///
  /// On the dose rather than kept somewhere of its own, so the rule in force
  /// is simply the latest dose's, and both caregivers see the same one
  /// without a second thing to keep in step.
  final int? waitHours;

  factory MedicationEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return MedicationEvent(
      id: doc.id,
      time: (data['time'] as Timestamp).toDate(),
      name: data['name'] as String,
      dose: (data['dose'] as num?)?.toDouble(),
      unit: DoseUnit.fromName(data['unit'] as String?),
      notes: data['notes'] as String?,
      createdBy: data['createdBy'] as String?,
      byName: data['byName'] as String?,
      waitHours: (data['waitHours'] as num?)?.toInt(),
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'time': Timestamp.fromDate(time),
    'name': name,
    'dose': dose,
    'unit': unit?.name,
    'notes': notes,
    'byName': byName,
    'waitHours': waitHours,
  };
}
