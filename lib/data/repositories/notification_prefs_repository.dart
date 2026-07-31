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

  /// Publishes just the reminder cadence, for the Cloud Function to read.
  ///
  /// Deliberately narrower than [save]: the reminder setting lives in local
  /// preferences and can be changed before the prefs stream has produced a
  /// value, so writing a whole [NotificationPrefs] here would push default
  /// quiet hours over whatever the caregiver had actually chosen.
  Future<void> saveReminderCadence({
    required int intervalMinutes,
    required bool remindersOff,
  }) => _doc.set({
    'reminderIntervalMinutes': intervalMinutes,
    'remindersOff': remindersOff,
  }, SetOptions(merge: true));
}
