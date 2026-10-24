import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby_event.dart';

/// The picture beside a checklist item. Stored by [name], so the artwork
/// (in the checklist feature) can change without touching the data.
enum ChecklistIcon {
  vitamin,
  tummyTime,
  bath,
  probiotic,
  iron,
  outside,
  other;

  /// [other] for a name this build does not know.
  static ChecklistIcon fromName(String? name) =>
      values.asNameMap()[name] ?? other;
}

/// Something done once a day — vitamin D, tummy time — that the household
/// wants to tick off.
///
/// Kept on the baby's profile as `checklist`, a list of these, so every
/// caregiver sees the same items in the same order.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.label,
    this.icon = ChecklistIcon.other,
  });

  /// What its checks point at. Stable across renames, so renaming an item
  /// keeps its streak.
  final String id;
  final String label;
  final ChecklistIcon icon;

  /// The longest label the rules accept.
  static const maxLabel = 40;

  /// The most items the rules accept: a strip on Home, not a to-do list.
  static const maxItems = 12;

  factory ChecklistItem.fromMap(Map<String, dynamic> map) => ChecklistItem(
    id: map['id'] as String? ?? '',
    label: map['label'] as String? ?? '',
    icon: ChecklistIcon.fromName(map['icon'] as String?),
  );

  Map<String, dynamic> toMap() => {'id': id, 'label': label, 'icon': icon.name};

  @override
  bool operator ==(Object other) =>
      other is ChecklistItem &&
      other.id == id &&
      other.label == label &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, label, icon);
}

/// The ready-made items offered in Settings. Ids are fixed, so adding the
/// same one on two phones makes the same item.
const checklistPresets = <ChecklistItem>[
  ChecklistItem(
    id: 'vitamin-d',
    label: 'Vitamin D',
    icon: ChecklistIcon.vitamin,
  ),
  ChecklistItem(
    id: 'tummy-time',
    label: 'Tummy time',
    icon: ChecklistIcon.tummyTime,
  ),
  ChecklistItem(id: 'bath', label: 'Bath', icon: ChecklistIcon.bath),
  ChecklistItem(
    id: 'probiotic',
    label: 'Probiotic',
    icon: ChecklistIcon.probiotic,
  ),
  ChecklistItem(id: 'iron', label: 'Iron', icon: ChecklistIcon.iron),
  ChecklistItem(
    id: 'outside',
    label: 'Outside time',
    icon: ChecklistIcon.outside,
  ),
];

/// One item ticked off. Stored at `babies/{babyId}/checks/{id}`.
///
/// A tick is a record that it was done, when and by whom; unticking deletes
/// it. Which day it counts for is the day of [time] on the phone reading it.
class DailyCheck implements BabyEvent {
  const DailyCheck({
    required this.id,
    required this.itemId,
    required this.time,
    this.label,
    this.createdBy,
    this.byName,
  });

  @override
  final String id;

  /// The [ChecklistItem.id] it ticks.
  final String itemId;
  final DateTime time;

  /// The item's name when it was ticked, so the activity log still reads
  /// right after the item is renamed or taken off the list. Null on ticks
  /// saved before it was kept.
  final String? label;

  /// Who ticked it, by account. Written by the repository on create.
  final String? createdBy;

  /// What to call whoever ticked it, as on a dose of medicine.
  final String? byName;

  factory DailyCheck.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return DailyCheck(
      id: doc.id,
      itemId: data['itemId'] as String,
      time: (data['time'] as Timestamp).toDate(),
      label: data['label'] as String?,
      createdBy: data['createdBy'] as String?,
      byName: data['byName'] as String?,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'time': Timestamp.fromDate(time),
    'label': label,
    'byName': byName,
  };
}
