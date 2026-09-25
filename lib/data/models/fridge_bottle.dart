import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'baby_event.dart';

/// What is in the bottle.
///
/// Worth distinguishing beyond labelling, because the two do not keep the
/// same way: expressed milk sits in a fridge for days, made-up formula for
/// hours. This screen does not put a number on either — how long is guidance
/// that belongs with whoever gave it, not baked into an app — but it has to
/// at least say which kind of clock a bottle is on.
enum BottleKind {
  /// Pumped. The timestamp is when it was expressed.
  expressed('Breast milk', 'Pumped', Icons.opacity),

  /// Powder and water. The timestamp is when it was mixed.
  formula('Formula', 'Made up', Icons.local_drink_outlined);

  const BottleKind(this.label, this.filledLabel, this.icon);

  /// What it is, for a card and a chooser.
  final String label;

  /// What its timestamp means. "Pumped 11:00" and "Made up 11:00" are
  /// different facts, and a bottle that says the wrong one is worse than one
  /// that says neither.
  final String filledLabel;

  final IconData icon;

  /// Expressed for anything stored before formula was supported, and for a
  /// value this version does not recognise. It is the commoner kind and the
  /// one the screen started life holding.
  static BottleKind fromName(String? name) =>
      values.asNameMap()[name] ?? BottleKind.expressed;
}

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
    this.kind = BottleKind.expressed,
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
  /// is [BottleKind.filledLabel]'s job to say.
  final DateTime filledAt;

  final double amountMl;

  final BottleKind kind;

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
    BottleKind? kind,
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
      kind: BottleKind.fromName(data['kind'] as String?),
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
