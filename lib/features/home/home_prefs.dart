import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';

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

/// What Home's activity list covers.
///
/// Two different questions, and the list can only answer one at a time.
/// "What has been happening" wants the last few entries whenever they were;
/// "how has today gone" wants today's record, complete, with yesterday's
/// late-evening feeds kept out of it.
enum HomeActivityScope {
  /// The most recent entries, whatever day they fall on.
  recent('Recent', 'The last few entries, whenever they were'),

  /// Today's entries only, from midnight.
  today('Today', "Today's entries only, from midnight");

  const HomeActivityScope(this.label, this.description);

  final String label;
  final String description;

  static HomeActivityScope fromName(String? name) =>
      values.asNameMap()[name] ?? HomeActivityScope.recent;
}

const _activityScopeKey = 'home_activity_scope';

/// Persisted, unlike the activity *filter* next to it.
///
/// The filter is deliberately in-memory, because a kind filter still applied
/// days later reads as missing data. This does not have that problem: both
/// options are labelled on screen, and "Today" showing only today is what it
/// says it does.
final homeActivityScopeProvider =
    NotifierProvider<HomeActivityScopeNotifier, HomeActivityScope>(
      HomeActivityScopeNotifier.new,
    );

class HomeActivityScopeNotifier extends Notifier<HomeActivityScope> {
  @override
  HomeActivityScope build() => HomeActivityScope.fromName(
    ref.read(sharedPreferencesProvider).getString(_activityScopeKey),
  );

  Future<void> setScope(HomeActivityScope scope) async {
    state = scope;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_activityScopeKey, scope.name);
  }
}

/// Where the quick-log buttons sit on Home.
///
/// Logging a feed is what the app is opened for, and it used to sit below the
/// status card and today's totals — around a third of the way down a phone,
/// and closer to half once solids and pumping are in play. That is a long
/// reach at 3am with a baby in the other arm.
enum HomeActions {
  /// Directly under the app bar, above everything else.
  top('Top', 'Right under the app bar, in reach one-handed'),

  /// Under the status rows, where they used to be.
  belowStatus('Below status', 'After the last-fed and diaper rows');

  const HomeActions(this.label, this.description);

  final String label;
  final String description;

  static HomeActions fromName(String? name) =>
      values.asNameMap()[name] ?? HomeActions.top;
}

const _homeActionsKey = 'home_actions';

final homeActionsProvider = NotifierProvider<HomeActionsNotifier, HomeActions>(
  HomeActionsNotifier.new,
);

class HomeActionsNotifier extends Notifier<HomeActions> {
  @override
  HomeActions build() => HomeActions.fromName(
    ref.read(sharedPreferencesProvider).getString(_homeActionsKey),
  );

  Future<void> setPlacement(HomeActions placement) async {
    state = placement;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_homeActionsKey, placement.name);
  }
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

const _displayModeKey = 'display_mode';

/// Whether the app is being held or propped up (#29).
///
/// An iPad on a nursery shelf is read from across the room and tapped while
/// holding a baby; a phone is held at arm's length and read closely. Those
/// want different amounts on screen, and no default can tell which one a
/// device is — which is exactly what a preference is for.
///
/// Per-device on purpose, and here that is right: the iPad wants nursery mode
/// and the phone does not. The feed interval was the opposite case and had to
/// follow the account instead (#27).
enum DisplayMode {
  /// The whole app: five tabs, lists, charts.
  normal('Normal', 'The full app'),

  /// Last fed, last changed, and three big buttons. Nothing else.
  nursery('Nursery', 'Big text and three buttons, for a propped-up tablet');

  const DisplayMode(this.label, this.description);

  final String label;
  final String description;

  static DisplayMode fromName(String? name) =>
      values.asNameMap()[name] ?? DisplayMode.normal;
}

final displayModeProvider = NotifierProvider<DisplayModeNotifier, DisplayMode>(
  DisplayModeNotifier.new,
);

class DisplayModeNotifier extends Notifier<DisplayMode> {
  @override
  DisplayMode build() => DisplayMode.fromName(
    ref.read(sharedPreferencesProvider).getString(_displayModeKey),
  );

  Future<void> setMode(DisplayMode mode) async {
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_displayModeKey, mode.name);
  }
}

