import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby_event.dart';

/// What a line of the diaper stock records. Stored by [name]; the rules
/// accept exactly these.
enum StockAction {
  /// A pack opened onto the pile: [DiaperStockEntry.count] more.
  added,

  /// The pile counted: there are [DiaperStockEntry.count], whatever the
  /// sums said. Where the count starts from.
  counted;

  static StockAction? fromName(String? name) => values.asNameMap()[name];
}

/// One line of the diaper stock: `babies/{babyId}/diaperStock/{id}`.
///
/// The stock itself is never stored. It is worked out from these and from
/// the diaper changes logged since the last count — see `DiaperStock` — so
/// logging a change is what uses one up, with nothing else to remember to
/// do, and two caregivers can never leave it saying two things.
class DiaperStockEntry implements BabyEvent {
  const DiaperStockEntry({
    required this.id,
    required this.action,
    required this.at,
    required this.count,
    this.notes,
  });

  @override
  final String id;

  final StockAction action;

  /// When the pack was added, or the pile counted.
  final DateTime at;

  /// How many were added, or counted.
  final int count;

  /// "Size 2", "Costco box": what a caregiver wants to say about it.
  final String? notes;

  /// Null for a line this version cannot read, which the stock skips rather
  /// than fails on.
  static DiaperStockEntry? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final action = StockAction.fromName(data?['action'] as String?);
    final at = data?['at'];
    final count = data?['count'];
    if (action == null || at is! Timestamp || count is! num) return null;
    return DiaperStockEntry(
      id: doc.id,
      action: action,
      at: at.toDate(),
      count: count.toInt(),
      notes: data!['notes'] as String?,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'action': action.name,
    'at': Timestamp.fromDate(at),
    'count': count,
    'notes': notes,
  };
}
