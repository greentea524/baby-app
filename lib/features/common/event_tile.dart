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
    required this.onTap,
    required this.onDelete,
    this.confirmTitle = 'Delete entry?',
    this.deletedMessage = 'Deleted',
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String trailing;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;
  final String confirmTitle;
  final String deletedMessage;

  Future<bool> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(confirmTitle),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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
        trailing: Text(trailing, style: Theme.of(context).textTheme.bodySmall),
        onTap: onTap,
      ),
    );
  }
}
