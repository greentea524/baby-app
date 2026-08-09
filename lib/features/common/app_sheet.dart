import 'package:flutter/material.dart';

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
///  * **The bottom inset has to be applied outside the scroll view**, so the
///    sheet is shortened to the space above the keyboard rather than scrolling
///    its content underneath it.
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
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
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
