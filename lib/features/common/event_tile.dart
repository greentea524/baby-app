import 'package:flutter/material.dart';

/// A log-entry row with tap-to-edit and swipe-to-delete (with confirm).
/// Shared by feeding, diaper, and the combined recent-activity list.
class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.trailingDetail,
    required this.onTap,
    required this.onDelete,
    this.confirmTitle = 'Delete entry?',
    this.deletedMessage = 'Deleted',
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String trailing;

  /// Optional second line under [trailing], dimmer and smaller — used to pair
  /// a relative "x ago" with the absolute clock time.
  final String? trailingDetail;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;
  final String confirmTitle;
  final String deletedMessage;

  Future<bool> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      // Use the dialog's own context to pop — popping via the outer context
      // targets go_router's page navigator and crashes ("popped the last
      // page off the stack").
      builder: (dialogContext) => AlertDialog(
        title: Text(confirmTitle),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: key ?? UniqueKey(),
      direction: DismissDirection.endToStart,
      // Delete inside confirmDismiss and always return false: the list is
      // driven by a Firestore stream that removes this row a frame later, so
      // actually "dismissing" would leave a dismissed widget in the tree for
      // a frame — which throws and white-screens. Returning false lets the
      // stream do the removal safely.
      confirmDismiss: (_) async {
        if (!await _confirm(context)) return false;
        await onDelete();
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(deletedMessage)));
        }
        return false;
      },
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete, color: scheme.onErrorContainer),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: (subtitle == null || subtitle!.isEmpty)
            ? null
            : Text(subtitle!),
        trailing: _Trailing(text: trailing, detail: trailingDetail),
        onTap: onTap,
      ),
    );
  }
}

/// Right-hand label: one line, or two when a [detail] stamp is supplied.
///
/// Width-bounded, because [ListTile] hands its trailing widget as much room
/// as it asks for and then gives the title what is left. At a large text size
/// a two-line stamp asked for most of a phone, and the row overflowed. A
/// fraction of the screen is a blunt cap, but it is one the timestamp always
/// fits inside — the text wraps within it rather than being clipped.
class _Trailing extends StatelessWidget {
  const _Trailing({required this.text, this.detail});

  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (detail == null) {
      return _bounded(context, Text(text, style: theme.textTheme.bodySmall));
    }
    return _bounded(context, _stamp(theme));
  }

  Widget _bounded(BuildContext context, Widget child) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.4,
    ),
    child: child,
  );

  Widget _stamp(ThemeData theme) => Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(text, style: theme.textTheme.bodySmall),
      Text(
        detail!,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
