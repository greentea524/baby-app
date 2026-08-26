import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/home_prefs.dart';

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

/// The cap in nursery mode, which is wider on purpose.
///
/// The cap exists to stop lines of text running too long. Nursery mode has no
/// long lines — two readouts and three buttons — and it is the one mode built
/// for a tablet propped on a stand, which is usually landscape. Holding it to
/// the reading width would leave three big buttons huddled in the middle of a
/// screen chosen for being large.
const double maxNurseryWidth = 900;

/// Holds [child] to [maxContentWidth], centred, with the surround painted.
///
/// Applied once around the router so every screen inherits it — sheets and
/// dialogs included, since they open inside the navigator this wraps.
///
/// The surround needs painting because the [Scaffold] inside now covers only
/// the middle: without it, an iPad shows the bare window either side.
class ContentWidth extends ConsumerWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nursery = ref.watch(displayModeProvider) == DisplayMode.nursery;
    final surround = Theme.of(context).colorScheme.surfaceContainerHighest;

    return ColoredBox(
      color: surround,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: nursery ? maxNurseryWidth : maxContentWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}
