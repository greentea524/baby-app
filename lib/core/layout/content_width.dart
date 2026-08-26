import 'package:flutter/material.dart';

/// The widest the app is ever laid out, whatever the screen (#29).
///
/// Nothing in the app was responsive: at 900pt the Home content ran from
/// x=92 to x=868, so a status row's label and its elapsed time sat most of a
/// screen apart, and the navigation bar stretched the full width of an iPad.
///
/// A phone layout centred on a tablet reads better than one pulled across it,
/// and there is nothing to lose on a phone, where the viewport is narrower
/// than this anyway. So it is not a preference — it is never the wrong thing.
const double maxContentWidth = 640;

/// Holds [child] to [maxContentWidth], centred, with the surround painted.
///
/// Applied once around the router so every screen inherits it — sheets and
/// dialogs included, since they open inside the navigator this wraps.
///
/// The surround needs painting because the [Scaffold] inside now covers only
/// the middle: without it, an iPad shows the bare window either side.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surround = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ColoredBox(
      color: surround,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: child,
        ),
      ),
    );
  }
}
