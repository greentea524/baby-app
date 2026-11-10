import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/diaper_stock_entry.dart';
import 'event_repository.dart';

/// The diaper stock's lines for one baby: `babies/{babyId}/diaperStock/{id}`.
class DiaperStockRepository extends TimelineRepository<DiaperStockEntry> {
  DiaperStockRepository(super.firestore, super.babyId, super.uid);

  @override
  String get collection => 'diaperStock';

  @override
  String get timeField => 'at';

  /// Lines this version cannot read are left out, not failed on.
  @override
  List<DiaperStockEntry> parse(QuerySnapshot<Map<String, dynamic>> snap) => [
    ...snap.docs.map(DiaperStockEntry.fromDoc).nonNulls,
  ];

  @override
  DiaperStockEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      DiaperStockEntry.fromDoc(doc)!;
}
