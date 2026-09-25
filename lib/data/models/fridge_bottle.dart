import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby_event.dart';
import 'milk_kind.dart';

export 'milk_kind.dart';

/// One bottle standing in the fridge. Stored at
/// `babies/{babyId}/bottles/{id}`.
///
/// Deliberately not derived from a pump session. A session is something that
/// happened and stays in the record forever; a bottle is something that is
/// *there now* and stops being there when it is poured. One session can become
/// two bottles, two sessions can be combined into one, milk fed straight from
/// the pump never reaches the fridge at all — and a formula bottle was never
/// pumped by anybody. So the fridge is its own list, added to and removed from
/// by hand.
class FridgeBottle implements BabyEvent {
  const FridgeBottle({
    required this.id,
    required this.filledAt,
    required this.amountMl,
    this.kind = MilkKind.expressed,
    this.position,
    this.notes,
  });

  @override
  final String id;

  /// When this became a bottle: expressed, or mixed. Not when it was written
  /// down — it is what decides how old the milk is, which is the whole
  /// question the shelf answers.
  ///
  /// One field for both kinds rather than two half-used ones. What it means
  /// is [MilkKind.filledLabel]'s job to say.
  final DateTime filledAt;

  final double amountMl;

  final MilkKind kind;

  /// Where this bottle sits on the shelf, or null while the shelf is still in
  /// age order.
  ///
  /// Null for every bottle until someone drags one, at which point the whole
  /// shelf is numbered at once. That is what makes "is this shelf arranged by
  /// hand" a question the data can answer, rather than a second stored flag
  /// that could disagree with the positions themselves.
  final int? position;

  final String? notes;

  FridgeBottle copyWith({
    DateTime? filledAt,
    double? amountMl,
    MilkKind? kind,
    int? position,
    String? notes,
  }) => FridgeBottle(
    id: id,
    filledAt: filledAt ?? this.filledAt,
    amountMl: amountMl ?? this.amountMl,
    kind: kind ?? this.kind,
    position: position ?? this.position,
    notes: notes ?? this.notes,
  );

  factory FridgeBottle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return FridgeBottle(
      id: doc.id,
      filledAt: (data['filledAt'] as Timestamp).toDate(),
      amountMl: (data['amountMl'] as num).toDouble(),
      kind: MilkKind.fromName(data['kind'] as String?),
      position: (data['position'] as num?)?.toInt(),
      notes: data['notes'] as String?,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'filledAt': Timestamp.fromDate(filledAt),
    'amountMl': amountMl,
    'kind': kind.name,
    'position': position,
    'notes': notes,
  };
}
