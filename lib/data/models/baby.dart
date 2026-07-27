import 'package:cloud_firestore/cloud_firestore.dart';

/// Biological sex, used for WHO growth percentiles (KAN-163).
enum BabySex { male, female }

/// Caregiver role on a baby (KAN-134).
enum CaregiverRole { owner, editor }

/// A picture for the profile, so caregivers with more than one baby can tell
/// them apart at a glance (KAN-168).
///
/// Emoji rather than image assets: they theme themselves, need no bundling or
/// network fetch, and render on every platform the app targets. Persisted by
/// [name], never by glyph, so the artwork can change without migrating data.
enum BabyAvatar {
  baby('👶', 'Baby'),
  bottle('🍼', 'Bottle'),
  teddy('🧸', 'Teddy'),
  bear('🐻', 'Bear'),
  bunny('🐰', 'Bunny'),
  fox('🦊', 'Fox'),
  panda('🐼', 'Panda'),
  koala('🐨', 'Koala'),
  chick('🐣', 'Chick'),
  lion('🦁', 'Lion'),
  frog('🐸', 'Frog'),
  star('🌟', 'Star');

  const BabyAvatar(this.emoji, this.label);

  final String emoji;
  final String label;

  /// Falls back to [BabyAvatar.baby] for profiles saved before avatars
  /// existed, or for a value this build doesn't recognise.
  static BabyAvatar fromName(String? name) =>
      values.asNameMap()[name] ?? BabyAvatar.baby;
}

/// A baby profile. Stored at the top-level `babies/{id}` so it can be shared
/// across caregiver accounts (KAN-134): [members] maps each caregiver's uid
/// to their role, and [memberUids] mirrors those keys as an array so the
/// list can be queried with `array-contains`.
class Baby {
  const Baby({
    required this.id,
    required this.name,
    required this.birthDate,
    required this.ownerUid,
    required this.members,
    this.sex,
    this.avatar = BabyAvatar.baby,
  });

  final String id;
  final String name;
  final DateTime birthDate;
  final BabySex? sex;
  final BabyAvatar avatar;
  final String ownerUid;
  final Map<String, CaregiverRole> members;

  List<String> get memberUids => members.keys.toList();

  bool isOwner(String uid) => ownerUid == uid;

  factory Baby.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final sexName = data['sex'] as String?;
    final rawMembers = (data['members'] as Map<String, dynamic>?) ?? const {};
    return Baby(
      id: doc.id,
      name: data['name'] as String,
      birthDate: (data['birthDate'] as Timestamp).toDate(),
      sex: sexName == null ? null : BabySex.values.asNameMap()[sexName],
      avatar: BabyAvatar.fromName(data['avatar'] as String?),
      ownerUid: data['ownerUid'] as String? ?? '',
      members: {
        for (final entry in rawMembers.entries)
          entry.key:
              CaregiverRole.values.asNameMap()[entry.value as String] ??
              CaregiverRole.editor,
      },
    );
  }

  /// Only the editable profile fields — membership is managed separately so
  /// a profile edit can never clobber the caregiver list.
  Map<String, dynamic> toProfileMap() => {
    'name': name,
    'birthDate': Timestamp.fromDate(birthDate),
    'sex': sex?.name,
    'avatar': avatar.name,
  };

  Baby copyWith({
    String? name,
    DateTime? birthDate,
    BabySex? sex,
    BabyAvatar? avatar,
  }) => Baby(
    id: id,
    name: name ?? this.name,
    birthDate: birthDate ?? this.birthDate,
    sex: sex ?? this.sex,
    avatar: avatar ?? this.avatar,
    ownerUid: ownerUid,
    members: members,
  );
}
