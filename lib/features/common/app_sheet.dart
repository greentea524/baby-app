import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How much to lift a sheet above the on-screen keyboard.
///
/// Native needs the inset: the keyboard covers the window, so a sheet that
/// does not pad by it has its lower half underneath the keys.
///
/// The web does not, and padding by it there is actively wrong. The browser
/// resizes the viewport when the keyboard opens — an iPhone showed the app's
/// own bottom navigation bar sitting directly above the keys, which is only
/// possible if the canvas had already been shortened — while Flutter goes on
/// reporting `viewInsets.bottom` as well. Padding by it then lifts the sheet
/// a second keyboard height, which is what pushed the bottle amount, and then
/// the solids food field, off the top of the screen.
///
/// If some browser ever fails to resize, the failure is mild and the opposite
/// way round: the sheet's lower rows sit under the keyboard and can be
/// scrolled up, because the content is inside a scroll view either way.
double sheetBottomInset({required double viewInset, bool isWeb = kIsWeb}) =>
    isWeb ? 0 : viewInset;

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
///  * **The bottom inset must not be counted twice.** On the web the browser
///    shrinks the viewport itself when the keyboard opens, and Flutter still
///    reports the inset on top of that — so padding by it pushed the sheet up
///    by a second keyboard's worth and took the field being typed into off
///    the top of the screen. See [sheetBottomInset].
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
    builder: (sheetContext) => Padding(
      // The sheet's context, not the caller's — see above.
      padding: EdgeInsets.only(
        bottom: sheetBottomInset(
          viewInset: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: padding,
          child: builder(sheetContext),
        ),
      ),
    ),
  );
}
