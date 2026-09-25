import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby_event.dart';

/// One bottle of expressed milk standing in the fridge. Stored at
/// `babies/{babyId}/bottles/{id}`.
///
/// Deliberately not derived from [PumpingEvent]. A pump session is something
/// that happened and stays in the record forever; a bottle is something that
/// is *there now* and stops being there when it is poured. One session can
/// become two bottles, two sessions can be combined into one, and milk fed
/// straight from the pump never reaches the fridge at all — so the fridge is
/// its own list, added to and removed from by hand.
class FridgeBottle implements BabyEvent {
  const FridgeBottle({
    required this.id,
    required this.pumpedAt,
    required this.amountMl,
    this.position,
    this.notes,
  });

  @override
  final String id;

  /// When the milk was expressed, not when the bottle was written down. It is
  /// what decides how old the milk is, which is the whole question the fridge
  /// shelf answers.
  final DateTime pumpedAt;

  final double amountMl;

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
    DateTime? pumpedAt,
    double? amountMl,
    int? position,
    String? notes,
  }) => FridgeBottle(
    id: id,
    pumpedAt: pumpedAt ?? this.pumpedAt,
    amountMl: amountMl ?? this.amountMl,
    position: position ?? this.position,
    notes: notes ?? this.notes,
  );

  factory FridgeBottle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return FridgeBottle(
      id: doc.id,
      pumpedAt: (data['pumpedAt'] as Timestamp).toDate(),
      amountMl: (data['amountMl'] as num).toDouble(),
      position: (data['position'] as num?)?.toInt(),
      notes: data['notes'] as String?,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'pumpedAt': Timestamp.fromDate(pumpedAt),
    'amountMl': amountMl,
    'position': position,
    'notes': notes,
  };
}
