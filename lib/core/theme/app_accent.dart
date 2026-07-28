import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_mode_provider.dart';

/// The colour the whole theme is generated from (KAN-180).
///
/// Deliberately a short list of seeds rather than a colour picker: Material 3
/// derives every surface, container, and accent from one seed, so an
/// arbitrary colour can quietly wreck contrast in dark mode. These four are
/// chosen to stay calm at both brightnesses.
enum AppAccent {
  blue('Blue', Color(0xFF7E9BD0)),
  sage('Sage', Color(0xFF7FA88B)),
  blush('Blush', Color(0xFFD08A9B)),
  lavender('Lavender', Color(0xFF9B8AD0));

  const AppAccent(this.label, this.seed);

  final String label;
  final Color seed;

  /// Falls back to the original palette for anything unrecognised.
  static AppAccent fromName(String? name) =>
      values.asNameMap()[name] ?? AppAccent.blue;
}

const _accentKey = 'app_accent';

final accentProvider = NotifierProvider<AccentNotifier, AppAccent>(
  AccentNotifier.new,
);

class AccentNotifier extends Notifier<AppAccent> {
  @override
  AppAccent build() => AppAccent.fromName(
    ref.read(sharedPreferencesProvider).getString(_accentKey),
  );

  Future<void> setAccent(AppAccent accent) async {
    state = accent;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_accentKey, accent.name);
  }
}
