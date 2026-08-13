import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/baby_event.dart';

/// One kind of event, for one baby, at `babies/{babyId}/{collection}`.
///
/// Four repositories were the same file with three words changed, which
/// meant a fix had to be applied four times to be applied at all. This repo
/// has already been bitten by that shape twice — five sheets each missing a
/// scroll view (#15), then nine that all hung offline (#21) — so the next
/// thing that touches reads or writes should land in one place (#23).
///
/// A subclass supplies three things: which collection, which field holds the
/// time, and how to read a document back. [uid] is the caregiver doing the
/// writing, stamped on for attribution (KAN-159) and checked by the security
/// rules (#22).
abstract class EventRepository<T extends BabyEvent> {
  EventRepository(this.firestore, this.babyId, this.uid);

  @protected
  final FirebaseFirestore firestore;
  @protected
  final String babyId;
  @protected
  final String uid;

  /// The subcollection under the baby: `feedings`, `diapers`, and so on.
  @protected
  String get collection;

  /// The field holding when the event happened. Every query orders by it,
  /// and the models disagree about its name — `startTime`, `time`, `date`,
  /// `at` — which is most of why these classes could not simply be one.
  @protected
  String get timeField;

  @protected
  T fromDoc(DocumentSnapshot<Map<String, dynamic>> doc);

  @protected
  CollectionReference<Map<String, dynamic>> get col =>
      firestore.collection('babies').doc(babyId).collection(collection);

  @protected
  List<T> parse(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(fromDoc).toList();

  /// Stores [event] and returns its id.
  ///
  /// The returned future is the write, so a caller that wants to know it
  /// failed can wait on it. Nothing waits on it to *close a sheet* — offline
  /// it would not complete until the device reconnects (#21).
  Future<String> add(T event) async {
    final doc = await col.add({
      ...event.toMap(),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Overwrites the stored fields of [event], leaving `createdBy` and
  /// `createdAt` as they were — the rules reject an edit that rewrites them.
  Future<void> update(T event) => col.doc(event.id).update({
    ...event.toMap(),
    'updatedBy': uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> delete(String id) => col.doc(id).delete();
}

/// An [EventRepository] whose events are also read back as a timeline: most
/// recent first for Home, a calendar day at a time for the timeline screen,
/// and a date range for export.
///
/// Split out because growth measurements and appointments are stored the
/// same way but never read like this — growth runs oldest-first for its
/// charts, appointments earliest-first because they are ahead of you. They
/// take the base directly rather than inheriting three queries that would
/// answer the wrong question.
abstract class TimelineRepository<T extends BabyEvent>
    extends EventRepository<T> {
  TimelineRepository(super.firestore, super.babyId, super.uid);

  /// Most recent first. [limit] keeps the home and history views cheap.
  Stream<List<T>> watchRecent({int limit = 50}) => col
      .orderBy(timeField, descending: true)
      .limit(limit)
      .snapshots()
      .map(parse);

  /// Everything on the local calendar [day], earliest first (KAN-132).
  Stream<List<T>> watchForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return _between(
      start,
      start.add(const Duration(days: 1)),
    ).snapshots().map(parse);
  }

  /// One-shot fetch of everything in [start, end), earliest first. Used by
  /// export (KAN-137) and insights, which want an answer rather than a feed.
  Future<List<T>> fetchRange(DateTime start, DateTime end) async =>
      parse(await _between(start, end).get());

  Query<Map<String, dynamic>> _between(DateTime start, DateTime end) => col
      .where(timeField, isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where(timeField, isLessThan: Timestamp.fromDate(end))
      .orderBy(timeField);
}
