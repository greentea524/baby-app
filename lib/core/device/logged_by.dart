import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../theme/theme_mode_provider.dart';

const _deviceNameKey = 'device_name';

/// The longest name a device can be given.
const deviceNameMax = 30;

/// What this phone or tablet is called on what it logs: "iPad", "Mom",
/// "Dad". Null until someone names it.
///
/// Per device rather than per account, because a household often shares
/// one account across several devices — and then every entry was "by you"
/// on all of them, which said nothing about who had actually done it.
final deviceNameProvider = NotifierProvider<DeviceNameNotifier, String?>(
  DeviceNameNotifier.new,
);

class DeviceNameNotifier extends Notifier<String?> {
  @override
  String? build() {
    final name = ref.read(sharedPreferencesProvider).getString(_deviceNameKey);
    return name == null || name.trim().isEmpty ? null : name.trim();
  }

  /// Names this device; blank clears it.
  Future<void> set(String? name) async {
    final trimmed = name?.trim() ?? '';
    final prefs = ref.read(sharedPreferencesProvider);
    if (trimmed.isEmpty) {
      state = null;
      await prefs.remove(_deviceNameKey);
    } else {
      final kept = trimmed.length > deviceNameMax
          ? trimmed.substring(0, deviceNameMax)
          : trimmed;
      state = kept;
      await prefs.setString(_deviceNameKey, kept);
    }
  }
}

/// The name written on what is logged from here: this device's name, or
/// failing that the account's — its display name, or the start of its
/// email address.
final loggedByProvider = Provider<String?>((ref) {
  final device = ref.watch(deviceNameProvider);
  if (device != null) return device;
  final user = ref.watch(authStateProvider).value;
  final name = user?.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return user?.email?.split('@').first;
});

/// Who logged an entry, as the app says it: "you" for something logged
/// under the name this device logs under, else that name.
///
/// Nothing for an entry from before names were written. Its account is no
/// answer: on an account shared between devices it would call every one of
/// them "you", which is what naming devices is for undoing.
String? whoLogged({required String? byName, required String? myName}) {
  final name = byName?.trim();
  if (name == null || name.isEmpty) return null;
  return name == myName ? 'you' : name;
}

/// Says who logged an entry, from the name it was logged under.
typedef WhoLogged = String? Function(String? byName);

/// [whoLogged] for whoever is using this device.
WhoLogged watchWhoLogged(WidgetRef ref) {
  final name = ref.watch(loggedByProvider);
  return (byName) => whoLogged(byName: byName, myName: name);
}
