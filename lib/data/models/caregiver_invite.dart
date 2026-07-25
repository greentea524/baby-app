import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby.dart';

/// A pending invitation for a caregiver to join a baby (KAN-134). Stored at
/// `babies/{babyId}/invites/{email}`; [babyName] is denormalised so the
/// invitee's list can show it without an extra read.
class CaregiverInvite {
  const CaregiverInvite({
    required this.babyId,
    required this.babyName,
    required this.email,
    required this.role,
    required this.invitedByUid,
  });

  final String babyId;
  final String babyName;
  final String email;
  final CaregiverRole role;
  final String invitedByUid;

  factory CaregiverInvite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CaregiverInvite(
      // babies/{babyId}/invites/{email}
      babyId: doc.reference.parent.parent!.id,
      babyName: data['babyName'] as String? ?? 'Baby',
      email: data['email'] as String? ?? doc.id,
      role:
          CaregiverRole.values.asNameMap()[data['role'] as String?] ??
          CaregiverRole.editor,
      invitedByUid: data['invitedByUid'] as String? ?? '',
    );
  }
}
