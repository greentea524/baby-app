import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How much to lift a sheet above the on-screen keyboard.
///
/// Native takes the inset: the keyboard covers the window, so a sheet that
/// does not pad by it has its lower half underneath the keys.
///
/// The web takes only the part of the keyboard the screen has not already
/// made room for. It can go either way there. While a field is being edited
/// Flutter keeps the screen its full height and reports the keyboard as an
/// inset — then the inset is all of it, and a sheet that ignored it had the
/// amount being typed hidden under the keys. But a browser can also shrink
/// the page for the keyboard and Flutter still report the inset on top —
/// an iPhone once showed the app's bottom bar sitting right above the keys
/// — and padding by the inset then lifted the sheet a second keyboard
/// height, off the top of the screen.
///
/// So: the inset, less however much shorter the screen is than
/// [fullHeight], its height with no keyboard up. Whichever way the browser
/// went, that is the part of the keyboard actually over the app.
double sheetBottomInset({
  required double viewInset,
  double? height,
  double? fullHeight,
  bool isWeb = kIsWeb,
}) {
  if (!isWeb || viewInset <= 0) return viewInset;
  final shrunk = height == null || fullHeight == null
      ? 0.0
      : (fullHeight - height).clamp(0.0, double.infinity);
  return (viewInset - shrunk).clamp(0.0, viewInset);
}

/// Drives the sheets as the web would, for tests; `kIsWeb` is fixed at
/// compile time and false wherever a test runs.
@visibleForTesting
bool? debugSheetIsWeb;

/// Opens one of the app's log/edit forms as a bottom sheet.
///
/// Shared because all five sheets need the same three things, and getting any
/// of them wrong is invisible on a desktop browser and broken on a phone:
///
///  * **The keyboard inset has to come from the sheet's own context.** Every
///    sheet used to read `MediaQuery.of(context)` off the *caller's* context,
///    captured by the closure while the builder's own context was discarded as
///    `_`. That registers the dependency against the calling widget rather
///    than anything inside the modal route, so the padding was not reliably
///    rebuilt when the keyboard changed the insets.
///
///  * **The content has to be scrollable.** Focusing a `TextField` asks its
///    enclosing scrollable to bring it into view; with no `Scrollable`
///    ancestor there is nothing to ask and the request is silently dropped. A
///    `MainAxisSize.min` column being squeezed by the keyboard then pushes the
///    field you are typing into off the top of the screen — which is exactly
///    what the bottle amount field did (#15).
///
///  * **The keyboard must be counted once.** On the web the screen may or
///    may not have shrunk for it already, and the inset is reported either
///    way. Counted twice, the field being typed into went off the top of the
///    screen; not at all, it sat under the keys. See [sheetBottomInset].
///
/// [builder] returns the form's content — normally a `Column` with
/// `MainAxisSize.min`. The safe area, the horizontal padding, and the scroll
/// view all live here, so a form should not add its own.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _KeyboardLift(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: padding,
          child: builder(sheetContext),
        ),
      ),
    ),
  );
}

/// Lifts [child] clear of the keyboard, by [sheetBottomInset].
///
/// Remembers how tall the screen is with no keyboard up, which is what tells
/// a browser that shrank the page for the keyboard from one that did not.
/// Read from the sheet's own context — see [showAppSheet].
class _KeyboardLift extends StatefulWidget {
  const _KeyboardLift({required this.child});

  final Widget child;

  @override
  State<_KeyboardLift> createState() => _KeyboardLiftState();
}

class _KeyboardLiftState extends State<_KeyboardLift> {
  Size? _withoutKeyboard;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final known = _withoutKeyboard;
    if (inset <= 0) {
      _withoutKeyboard = size;
    } else if (known == null || known.width != size.width) {
      // Opened with the keyboard already up, or turned while it was: no
      // height without it to go on, so take the screen as not shrunk for it,
      // which is how Flutter keeps it while a field is being edited.
      _withoutKeyboard = size;
    }
    return Padding(
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(
          viewInset: inset,
          height: size.height,
          fullHeight: _withoutKeyboard!.height,
          isWeb: debugSheetIsWeb ?? kIsWeb,
        ),
      ),
      child: widget.child,
    );
  }
}
