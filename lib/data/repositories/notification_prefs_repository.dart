import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_prefs.dart';

/// Reads/writes one caregiver's notification preferences at
/// `notificationPrefs/{uid}` (KAN-167).
///
/// Stored per user rather than per baby: quiet hours follow the person, not
/// the child, and a caregiver on several babies wants one setting.
class NotificationPrefsRepository {
  NotificationPrefsRepository(this._firestore, this._uid);

  final FirebaseFirestore _firestore;
  final String _uid;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('notificationPrefs').doc(_uid);

  /// Emits defaults until the user has saved anything.
  Stream<NotificationPrefs> watch() =>
      _doc.snapshots().map(NotificationPrefs.fromDoc);

  Future<void> save(NotificationPrefs prefs) =>
      _doc.set(prefs.toMap(), SetOptions(merge: true));
}
