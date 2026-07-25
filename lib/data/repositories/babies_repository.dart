import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/baby.dart';
import '../models/caregiver_invite.dart';

/// Reads/writes shared baby profiles at the top-level `babies/{babyId}`
/// collection (KAN-134). Access is by membership: a user sees the babies
/// whose `memberUids` array contains their uid.
class BabiesRepository {
  BabiesRepository(this._firestore, this._uid);

  final FirebaseFirestore _firestore;
  final String _uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('babies');

  DocumentReference<Map<String, dynamic>> _baby(String id) => _col.doc(id);

  CollectionReference<Map<String, dynamic>> _invites(String babyId) =>
      _baby(babyId).collection('invites');

  String _emailKey(String email) => email.trim().toLowerCase();

  /// The babies the current user is a member of, sorted by birth date.
  /// Sorted client-side to avoid a composite (array-contains + orderBy) index.
  Stream<List<Baby>> watchBabies() {
    return _col
        .where('memberUids', arrayContains: _uid)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(Baby.fromDoc).toList()
                ..sort((a, b) => a.birthDate.compareTo(b.birthDate)),
        );
  }

  Future<String> addBaby({
    required String name,
    required DateTime birthDate,
    BabySex? sex,
  }) async {
    final doc = await _col.add({
      'name': name,
      'birthDate': Timestamp.fromDate(birthDate),
      'sex': sex?.name,
      'ownerUid': _uid,
      'members': {_uid: CaregiverRole.owner.name},
      'memberUids': [_uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Updates only the profile fields; never touches membership.
  Future<void> updateBaby(Baby baby) =>
      _baby(baby.id).update(baby.toProfileMap());

  Future<void> deleteBaby(String id) => _baby(id).delete();

  // --- Caregiver membership (KAN-134) --------------------------------------

  /// Invites [email] to join [babyId] with [role]. The invitee accepts once
  /// they sign in with that address.
  Future<void> inviteCaregiver({
    required String babyId,
    required String babyName,
    required String email,
    CaregiverRole role = CaregiverRole.editor,
  }) {
    return _invites(babyId).doc(_emailKey(email)).set({
      'email': _emailKey(email),
      'babyName': babyName,
      'role': role.name,
      'invitedByUid': _uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<CaregiverInvite>> watchInvitesForBaby(String babyId) {
    return _invites(babyId).snapshots().map(
      (snap) => snap.docs.map(CaregiverInvite.fromDoc).toList(),
    );
  }

  Future<void> revokeInvite(String babyId, String email) =>
      _invites(babyId).doc(_emailKey(email)).delete();

  /// Owner removes a caregiver (or a caregiver removes themselves).
  Future<void> removeMember(String babyId, String uid) {
    return _baby(babyId).update({
      'members.$uid': FieldValue.delete(),
      'memberUids': FieldValue.arrayRemove([uid]),
    });
  }

  Future<void> leaveBaby(String babyId) => removeMember(babyId, _uid);

  /// Pending invitations addressed to [email], across all babies.
  Stream<List<CaregiverInvite>> watchIncomingInvites(String email) {
    return _firestore
        .collectionGroup('invites')
        .where('email', isEqualTo: _emailKey(email))
        .snapshots()
        .map((snap) => snap.docs.map(CaregiverInvite.fromDoc).toList());
  }

  /// Accepts [invite]: adds the current user to the baby's members, then
  /// clears the invite.
  Future<void> acceptInvite(CaregiverInvite invite) async {
    await _baby(invite.babyId).update({
      'members.$_uid': invite.role.name,
      'memberUids': FieldValue.arrayUnion([_uid]),
    });
    await _invites(invite.babyId).doc(invite.email).delete();
  }

  Future<void> declineInvite(CaregiverInvite invite) =>
      _invites(invite.babyId).doc(invite.email).delete();
}
