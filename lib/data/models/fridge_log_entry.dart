import 'package:cloud_firestore/cloud_firestore.dart';

import 'fridge_bottle.dart';

/// What happened to a bottle in the fridge. Stored by [name]; the rules
/// accept exactly these.
enum FridgeAction {
  /// Put on the shelf, by hand or from a pump session.
  added,

  /// Taken off without being fed: poured away, or tapped by mistake. The one
  /// that can be put back.
  removed,

  /// Fed: taken off as a bottle feed was logged from it.
  fed,

  /// Divided into two bottles; [FridgeLogEntry.otherMl] is the new one.
  split,

  /// Poured into another; [FridgeLogEntry.otherMl] is how much went.
  combined,

  /// Put back on the shelf after being removed.
  restored;

  static FridgeAction? fromName(String? name) => values.asNameMap()[name];
}

/// One line of the fridge's history: `babies/{babyId}/fridgeLog/{id}`.
///
/// The shelf is what is there now; this is what happened to it, for the
/// fridge screen alone. Written in the same batch as the change it records,
/// so the two never disagree. Carries the bottle as it was, which is what
/// putting a removed one back needs.
class FridgeLogEntry {
  const FridgeLogEntry({
    required this.id,
    required this.action,
    required this.at,
    required this.bottleId,
    required this.amountMl,
    required this.kind,
    required this.filledAt,
    this.notes,
    this.otherMl,
  });

  final String id;
  final FridgeAction action;

  /// When it happened.
  final DateTime at;

  /// The bottle it happened to, which is the id a removed one comes back
  /// under.
  final String bottleId;

  /// The bottle as it stood just before: its amount, kind, age and notes.
  final double amountMl;
  final MilkKind kind;
  final DateTime filledAt;
  final String? notes;

  /// For a split, how much went into the new bottle; for a combine, how much
  /// was poured into the other.
  final double? otherMl;

  /// An entry about [bottle], as it stood before [action].
  factory FridgeLogEntry.of(
    FridgeAction action,
    FridgeBottle bottle, {
    required DateTime at,
    double? otherMl,
  }) => FridgeLogEntry(
    id: '',
    action: action,
    at: at,
    bottleId: bottle.id,
    amountMl: bottle.amountMl,
    kind: bottle.kind,
    filledAt: bottle.filledAt,
    notes: bottle.notes,
    otherMl: otherMl,
  );

  /// The bottle as it was, under its old id: what putting it back puts.
  FridgeBottle get bottle => FridgeBottle(
    id: bottleId,
    filledAt: filledAt,
    amountMl: amountMl,
    kind: kind,
    notes: notes,
  );

  /// Null for an entry this version cannot read, which the history skips
  /// rather than fails on.
  static FridgeLogEntry? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final action = FridgeAction.fromName(data?['action'] as String?);
    if (data == null || action == null) return null;
    return FridgeLogEntry(
      id: doc.id,
      action: action,
      at: (data['at'] as Timestamp).toDate(),
      bottleId: data['bottleId'] as String,
      amountMl: (data['amountMl'] as num).toDouble(),
      kind: MilkKind.fromName(data['kind'] as String?),
      filledAt: (data['filledAt'] as Timestamp).toDate(),
      notes: data['notes'] as String?,
      otherMl: (data['otherMl'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'action': action.name,
    'at': Timestamp.fromDate(at),
    'bottleId': bottleId,
    'amountMl': amountMl,
    'kind': kind.name,
    'filledAt': Timestamp.fromDate(filledAt),
    'notes': notes,
    'otherMl': otherMl,
  };
}
