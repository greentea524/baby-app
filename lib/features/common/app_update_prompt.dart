import 'package:flutter/material.dart';

import '../../core/web/app_update.dart' as platform;

/// Says when a new version of the web app is ready, and switches to it.
///
/// The app opens from its own saved copy so it works with no signal (#34),
/// so a deploy reaches an open app as a download in the background rather
/// than on the next load. Without this the app would go on running the old
/// version until some reload nobody knew to do.
///
/// Asked rather than done: switching reloads the page, and a reload in the
/// middle of typing a note would lose it.
class AppUpdatePrompt extends StatefulWidget {
  const AppUpdatePrompt({
    super.key,
    required this.child,
    this.onReady = platform.onAppUpdateReady,
    this.apply = platform.applyAppUpdate,
  });

  final Widget child;

  /// Registers a callback for when a new version is waiting. Injectable for
  /// tests.
  final void Function(void Function() ready) onReady;

  /// Switches to it. Injectable for tests.
  final VoidCallback apply;

  @override
  State<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends State<AppUpdatePrompt> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    widget.onReady(_announce);
  }

  void _announce() {
    if (_shown || !mounted) return;
    _shown = true;
    // After the frame: this can be called while the tree is being built,
    // and a snack bar cannot be shown from inside a build. And a frame asked
    // for, since the call usually comes from the browser while the app sits
    // idle drawing nothing — and an idle app has no next frame to wait for.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('A new version of the app is ready'),
          // Until it is acted on or closed: it is the only time it is said.
          duration: const Duration(days: 1),
          showCloseIcon: true,
          action: SnackBarAction(label: 'Reload', onPressed: widget.apply),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
