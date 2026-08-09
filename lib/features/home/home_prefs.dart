import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import 'companion_art.dart';

/// How the Home status rows are grouped (KAN-180).
///
/// Feeding, diapers, and the next visit are the same three rows either way —
/// this only changes whether they share one card or get their own. Kept as a
/// presentation choice rather than two layouts so there is one set of rows to
/// maintain.
enum HomeLayout {
  /// One card, rows separated by dividers. Compact, less scrolling.
  combined('Combined', 'One card for everything'),

  /// A card per row. Airier, and each section reads as its own thing.
  separate('Separate', 'A card per section');

  const HomeLayout(this.label, this.description);

  final String label;
  final String description;

  static HomeLayout fromName(String? name) =>
      values.asNameMap()[name] ?? HomeLayout.combined;
}

const _homeLayoutKey = 'home_layout';

final homeLayoutProvider = NotifierProvider<HomeLayoutNotifier, HomeLayout>(
  HomeLayoutNotifier.new,
);

class HomeLayoutNotifier extends Notifier<HomeLayout> {
  @override
  HomeLayout build() => HomeLayout.fromName(
    ref.read(sharedPreferencesProvider).getString(_homeLayoutKey),
  );

  Future<void> setLayout(HomeLayout layout) async {
    state = layout;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_homeLayoutKey, layout.name);
  }
}

const _companionStyleKey = 'home_companion_style';

/// The key this setting used while it was a plain on/off switch for the
/// plane. Read once, to carry an existing choice across (#16).
const _legacyShowPlaneKey = 'show_feed_plane';

/// Which companion Home flies in the app bar corner (#14, #16).
///
/// Defaults to the plane rather than to off: it is a decoration nobody has to
/// interact with, and one that hides behind a setting before it has ever been
/// seen is one nobody finds.
final companionStyleProvider =
    NotifierProvider<CompanionStyleNotifier, CompanionStyle>(
      CompanionStyleNotifier.new,
    );

class CompanionStyleNotifier extends Notifier<CompanionStyle> {
  @override
  CompanionStyle build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final stored = prefs.getString(_companionStyleKey);
    if (stored != null) return CompanionStyle.fromName(stored);

    // No style stored yet, so this is either a fresh install or someone
    // upgrading from the switch. Reading the old key keeps a caregiver who
    // turned the plane off from having it handed back to them.
    return prefs.getBool(_legacyShowPlaneKey) == false
        ? CompanionStyle.off
        : CompanionStyle.plane;
  }

  Future<void> setStyle(CompanionStyle style) async {
    state = style;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_companionStyleKey, style.name);
  }
}

const _showPumpingKey = 'show_pumping_action';

/// Whether Home offers a "Log pumping" button (KAN-181).
///
/// On by default, because this button is the only way to *create* a pump
/// entry — the activity list can edit existing sessions but not start new
/// ones. Defaulting it off would silently make pump logging unreachable, so
/// hiding it is a deliberate choice the caregiver makes rather than one they
/// discover the hard way.
final showPumpingActionProvider =
    NotifierProvider<ShowPumpingActionNotifier, bool>(
      ShowPumpingActionNotifier.new,
    );

class ShowPumpingActionNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(_showPumpingKey) ?? true;

  Future<void> set(bool value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setBool(_showPumpingKey, value);
  }
}
