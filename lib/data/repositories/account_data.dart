import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/baby.dart';
import 'baby_data.dart';

/// What deleting an account amounts to, and how much of it there is (#28).
///
/// Scope A — deleting one baby — took nearly all the *volume* and almost none
/// of the *identity*: the email address stayed in two places, and so did the
/// push tokens and the reminder preferences. This is the other half.
class AccountData {
  AccountData(this._firestore, this._babies);

  final FirebaseFirestore _firestore;
  final BabyData _babies;

  /// Babies split by what deleting the account should do with each.
  ///
  /// Owned ones go entirely; the rest are only left. A caregiver invited to
  /// someone else's baby has no business destroying it on the way out, and
  /// the rules would refuse anyway — a member may remove exactly themselves.
  static ({List<Baby> owned, List<Baby> shared}) split(
    List<Baby> babies,
    String uid,
  ) => (
    owned: babies.where((b) => b.isOwner(uid)).toList(),
    shared: babies.where((b) => !b.isOwner(uid)).toList(),
  );

  /// Deletes everything this account owns, then everything about the account
  /// itself, and finally lets go of the babies it merely shared.
  ///
  /// Firestore first and the auth user last, in the caller: every write here
  /// needs a signed-in user, so deleting the account before its data would
  /// strand the data exactly the way scope A's ordering bug did.
  Future<void> deleteAll({
    required String uid,
    required String email,
    required List<Baby> babies,
    void Function(int)? onProgress,
  }) async {
    final parts = split(babies, uid);

    for (final baby in parts.owned) {
      await _babies.deleteAll(baby.id, onProgress: onProgress);
    }

    // Not deleted, left. The data belongs to whoever else is on it.
    for (final baby in parts.shared) {
      await _firestore.collection('babies').doc(baby.id).update({
        'members.$uid': FieldValue.delete(),
        'memberUids': FieldValue.arrayRemove([uid]),
      });
    }

    await _deleteNotificationPrefs(uid);
    await _deletePushTokens(uid);
    await _deleteAllowlistEntry(email);
  }

  Future<void> _deleteNotificationPrefs(String uid) =>
      _firestore.collection('notificationPrefs').doc(uid).delete();

  /// One per device this account has ever signed in on.
  Future<void> _deletePushTokens(String uid) async {
    final tokens = await _firestore
        .collection('fcmTokens')
        .where('uid', isEqualTo: uid)
        .get(const GetOptions(source: Source.server));
    for (final doc in tokens.docs) {
      await doc.reference.delete();
    }
  }

  /// The address itself, which is the part a person means by "my data".
  ///
  /// One-way: there is no rule to write one back, so returning means someone
  /// adding the address again by hand in the console.
  Future<void> _deleteAllowlistEntry(String email) => _firestore
      .collection('allowedUsers')
      .doc(email.trim().toLowerCase())
      .delete();
}
