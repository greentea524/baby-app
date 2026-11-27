import 'dart:async';

import 'package:flutter/material.dart';

/// Delete, from inside an entry's edit sheet, with a confirmation (#42).
///
/// Rows in the activity list, the timeline, growth and appointments delete
/// by swiping, which a mouse, a keyboard or a screen reader cannot easily
/// do, and which nothing on screen announces. This is the same delete in a
/// place all of them reach: under Save, in the sheet the row opens. Swiping
/// still works on a phone.
class DeleteEntryButton extends StatelessWidget {
  const DeleteEntryButton({
    super.key,
    required this.label,
    required this.confirmTitle,
    required this.deletedMessage,
    required this.onDelete,
  });

  /// "Delete feed".
  final String label;

  /// "Delete feed?"
  final String confirmTitle;

  /// "Feed deleted".
  final String deletedMessage;

  /// Null when there is nothing to delete with (signed out): the button is
  /// shown disabled rather than hidden, so the sheet does not change shape.
  final Future<void> Function()? onDelete;

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
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
    if (ok != true || !context.mounted) return;
    // Looked up before the sheet closes, whose context then goes.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    // Not awaited: offline it would not finish until the device is back
    // online (#21), and the entry leaves the list straight away regardless.
    unawaited(
      Future<void>.sync(onDelete!).catchError((Object e) {
        messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }),
    );
    messenger.showSnackBar(SnackBar(content: Text(deletedMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextButton.icon(
        key: const ValueKey('delete-entry'),
        style: TextButton.styleFrom(foregroundColor: error),
        onPressed: onDelete == null ? null : () => _delete(context),
        icon: const Icon(Icons.delete_outline),
        label: Text(label),
      ),
    );
  }
}
