import 'package:cloud_firestore/cloud_firestore.dart';

enum DiaperType { wet, dirty, both }

/// How much was in a dirty diaper (#20).
///
/// Optional everywhere. Someone logging a change one-handed at 3am should not
/// be made to answer a second question, so "not saying" is a first-class
/// answer rather than a gap to be filled in later.
enum PoopSize {
  small('Small'),
  medium('Medium'),
  large('Large');

  const PoopSize(this.label);

  final String label;

  /// Tolerant of null and of a value this build does not know, since both
  /// mean the same thing to a reader: no size recorded.
  static PoopSize? fromName(String? name) =>
      name == null ? null : values.asNameMap()[name];
}

/// A diaper change. Stored at `users/{uid}/babies/{babyId}/diapers/{id}`.
/// Full CRUD lands with the Diaper Change Logging epic (KAN-131).
class DiaperEvent {
  /// A wet-only change cannot carry a size, so it is dropped here rather than
  /// guarded at every place that reads one. That makes the bad state
  /// unrepresentable instead of merely unlikely — including for a record
  /// already stored that way.
  DiaperEvent({
    required this.id,
    required this.type,
    required this.time,
    this.notes,
    PoopSize? poopSize,
  }) : poopSize = type == DiaperType.wet ? null : poopSize;

  final String id;
  final DiaperType type;
  final DateTime time;
  final String? notes;

  /// How big it was, or null when nobody said.
  final PoopSize? poopSize;

  /// Whether this change has a poop component, and so can carry a
  /// [poopSize].
  bool get hasPoop => type != DiaperType.wet;

  factory DiaperEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return DiaperEvent(
      id: doc.id,
      type: DiaperType.values.byName(data['type'] as String),
      time: (data['time'] as Timestamp).toDate(),
      notes: data['notes'] as String?,
      // Absent on every change logged before sizes existed.
      poopSize: PoopSize.fromName(data['poopSize'] as String?),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'time': Timestamp.fromDate(time),
    'notes': notes,
    'poopSize': poopSize?.name,
  };
}
