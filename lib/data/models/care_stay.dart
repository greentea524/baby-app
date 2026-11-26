import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby_event.dart';
import 'milk_kind.dart';

/// A stretch of time the baby spends in someone else's care — grandparents,
/// a sitter, daycare — from drop-off to pick-up. Stored at
/// `babies/{babyId}/stays/{id}`.
///
/// While it lasts, nobody at home is there to log a feed, so the app logs
/// them itself at each due time when [autoFeed] is on (see `auto_feed.dart`),
/// and the diaper row stops warning about a change nobody can make.
class CareStay implements BabyEvent {
  const CareStay({
    required this.id,
    required this.droppedAt,
    required this.carer,
    required this.intervalMinutes,
    this.pickedUpAt,
    this.autoFeed = true,
    this.amountMl,
    this.milk,
    this.autoUntil,
  });

  @override
  final String id;

  final DateTime droppedAt;

  /// Null while the baby is still away.
  final DateTime? pickedUpAt;

  /// Who has the baby, as the caregiver put it: "Grandparents", "Sitter".
  final String carer;

  /// Whether feeds are logged automatically while away.
  final bool autoFeed;

  /// What each automatic feed is logged as.
  final double? amountMl;
  final MilkKind? milk;

  /// The gap between automatic feeds, fixed at drop-off from that device's
  /// feed interval, so every device fills in the same times.
  final int intervalMinutes;

  /// The latest due time an automatic feed has been logged for. Feeds are
  /// only ever logged after it, so one deleted by hand is not put back.
  final DateTime? autoUntil;

  bool get isActive => pickedUpAt == null;

  Duration get interval => Duration(minutes: intervalMinutes);

  /// The id every automatic feed from this stay starts with.
  String get autoFeedPrefix => 'auto-$id-';

  CareStay copyWith({
    DateTime? pickedUpAt,
    bool clearPickedUp = false,
    DateTime? autoUntil,
  }) => CareStay(
    id: id,
    droppedAt: droppedAt,
    pickedUpAt: clearPickedUp ? null : (pickedUpAt ?? this.pickedUpAt),
    carer: carer,
    autoFeed: autoFeed,
    amountMl: amountMl,
    milk: milk,
    intervalMinutes: intervalMinutes,
    autoUntil: autoUntil ?? this.autoUntil,
  );

  factory CareStay.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    DateTime? time(Object? v) => (v as Timestamp?)?.toDate();
    return CareStay(
      id: doc.id,
      droppedAt: (data['droppedAt'] as Timestamp).toDate(),
      pickedUpAt: time(data['pickedUpAt']),
      carer: data['carer'] as String? ?? '',
      autoFeed: data['autoFeed'] as bool? ?? false,
      amountMl: (data['amountMl'] as num?)?.toDouble(),
      milk: MilkKind.values.asNameMap()[data['milk']],
      intervalMinutes: data['intervalMinutes'] as int? ?? 180,
      autoUntil: time(data['autoUntil']),
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'droppedAt': Timestamp.fromDate(droppedAt),
    'pickedUpAt': pickedUpAt == null ? null : Timestamp.fromDate(pickedUpAt!),
    'carer': carer,
    'autoFeed': autoFeed,
    'amountMl': amountMl,
    'milk': milk?.name,
    'intervalMinutes': intervalMinutes,
    'autoUntil': autoUntil == null ? null : Timestamp.fromDate(autoUntil!),
  };
}
