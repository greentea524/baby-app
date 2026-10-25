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
    this.perDay = 1,
    this.minutes,
  });

  /// What its checks point at. Stable across renames, so renaming an item
  /// keeps its streak.
  final String id;
  final String label;
  final ChecklistIcon icon;

  /// How many times a day makes it done: one for vitamin D, a few for tummy
  /// time, ticked a session at a time and shown as "2/5" until it is.
  final int perDay;

  /// A daily goal in minutes, for an item done for a length of time rather
  /// than a number of times: thirty minutes of tummy time, built up through
  /// the day from a timer or minutes added by hand. Null for an item that is
  /// counted; when set, [perDay] is not used.
  final int? minutes;

  bool get timed => minutes != null;

  /// What a day has to reach: minutes for a timed item, times otherwise.
  int get goal => minutes ?? perDay;

  /// The most times a day an item can ask for.
  static const maxPerDay = 12;

  /// The longest daily goal in minutes, and the longest one session can be.
  static const maxMinutes = 240;

  /// The longest label the rules accept.
  static const maxLabel = 40;

  /// The most items the rules accept: a strip on Home, not a to-do list.
  static const maxItems = 12;

  factory ChecklistItem.fromMap(Map<String, dynamic> map) => ChecklistItem(
    id: map['id'] as String? ?? '',
    label: map['label'] as String? ?? '',
    icon: ChecklistIcon.fromName(map['icon'] as String?),
    // One for an item saved before there was a choice.
    perDay: ((map['perDay'] as num?)?.toInt() ?? 1).clamp(1, maxPerDay),
    minutes: switch ((map['minutes'] as num?)?.toInt()) {
      null => null,
      final m => m.clamp(1, maxMinutes),
    },
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'icon': icon.name,
    'perDay': perDay,
    'minutes': minutes,
  };

  /// This item renamed, or with a new goal: [minutes] for a timed one, or
  /// [perDay] times with no minutes for a counted one.
  ChecklistItem withGoal({
    required String label,
    int perDay = 1,
    int? minutes,
  }) => ChecklistItem(
    id: id,
    label: label,
    icon: icon,
    perDay: minutes == null ? perDay : 1,
    minutes: minutes,
  );

  @override
  bool operator ==(Object other) =>
      other is ChecklistItem &&
      other.id == id &&
      other.label == label &&
      other.icon == icon &&
      other.perDay == perDay &&
      other.minutes == minutes;

  @override
  int get hashCode => Object.hash(id, label, icon, perDay, minutes);
}

/// The ready-made items offered in Settings. Ids are fixed, so adding the
/// same one on two phones makes the same item.
const checklistPresets = <ChecklistItem>[
  ChecklistItem(
    id: 'vitamin-d',
    label: 'Vitamin D',
    icon: ChecklistIcon.vitamin,
  ),
  // Built up through the day from short sessions, timed or added by hand.
  ChecklistItem(
    id: 'tummy-time',
    label: 'Tummy time',
    icon: ChecklistIcon.tummyTime,
    minutes: 30,
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
/// A tick is a record that it was done, when and by whom — or for an item
/// done several times a day, one of those times; unticking deletes it.
/// Which day it counts for is the day of [time] on the phone reading it.
class DailyCheck implements BabyEvent {
  const DailyCheck({
    required this.id,
    required this.itemId,
    required this.time,
    this.label,
    this.minutes,
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

  /// How long it went on, for a timed item: what counts towards the day's
  /// goal. Null for an item that is counted.
  final int? minutes;

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
      minutes: (data['minutes'] as num?)?.toInt(),
      createdBy: data['createdBy'] as String?,
      byName: data['byName'] as String?,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'time': Timestamp.fromDate(time),
    'label': label,
    'minutes': minutes,
    'byName': byName,
  };
}
