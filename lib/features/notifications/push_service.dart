import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../data/repositories/repository_providers.dart';

/// Web Push (VAPID) public key, from Firebase console → Project settings →
/// Cloud Messaging → "Web Push certificates". Required to mint web push
/// tokens. Supply at build time: `--dart-define=VAPID_KEY=...`.
const kWebPushVapidKey = String.fromEnvironment('VAPID_KEY');

/// Registers this device for push and records its FCM token so the reminder
/// Cloud Function (KAN-156) can target the caregiver. Tokens live at
/// `fcmTokens/{token}` keyed by uid.
class PushService {
  PushService(this._messaging, this._firestore);

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  String? get _vapid => kWebPushVapidKey.isEmpty ? null : kWebPushVapidKey;

  /// Requests permission and stores the token. Returns false if the user
  /// declined or no token could be obtained (e.g. VAPID key missing).
  Future<bool> enable(String uid) async {
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }
    final token = await _messaging.getToken(vapidKey: _vapid);
    if (token == null) return false;
    await _firestore.collection('fcmTokens').doc(token).set({
      'uid': uid,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  Future<void> disable() async {
    final token = await _messaging.getToken(vapidKey: _vapid);
    if (token != null) {
      await _firestore.collection('fcmTokens').doc(token).delete();
    }
    await _messaging.deleteToken();
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(FirebaseMessaging.instance, ref.watch(firestoreProvider));
});

const _pushEnabledKey = 'push_enabled';

/// Whether the user opted into background push. Persisted; toggling it
/// registers/unregisters the device token.
final pushEnabledProvider = NotifierProvider<PushEnabledNotifier, bool>(
  PushEnabledNotifier.new,
);

class PushEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(_pushEnabledKey) ?? false;

  /// Enables or disables push. Returns false if enabling was refused (e.g.
  /// permission denied) so the UI can reflect the real state.
  Future<bool> set(bool value, String? uid) async {
    final push = ref.read(pushServiceProvider);
    var effective = value;
    if (value) {
      effective = uid != null && await push.enable(uid);
    } else {
      await push.disable();
    }
    state = effective;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_pushEnabledKey, effective);
    return effective;
  }
}
