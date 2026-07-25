import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The `action` the app was launched with via a PWA shortcut (KAN-166),
/// e.g. `feed` or `diaper` from `/?action=feed`. Set once from the launch
/// URL in main(); the Home screen consumes it to open the matching
/// quick-log sheet, then clears it.
final initialLaunchActionProvider = Provider<String?>((_) => null);

final launchActionProvider = NotifierProvider<LaunchActionNotifier, String?>(
  LaunchActionNotifier.new,
);

class LaunchActionNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(initialLaunchActionProvider);

  void consume() => state = null;
}
