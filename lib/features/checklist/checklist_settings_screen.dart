import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/baby.dart';
import '../../data/models/daily_check.dart';
import '../../data/repositories/repository_providers.dart';
import 'checklist_logic.dart';

/// Settings' line for the daily checklist: what is on it, and the way in.
class ChecklistSettingsTile extends ConsumerWidget {
  const ChecklistSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(currentBabyProvider);
    if (baby == null) return const SizedBox.shrink();
    final items = baby.checklist;
    return ListTile(
      leading: const Icon(Icons.checklist),
      title: const Text('Daily checklist'),
      subtitle: Text(
        items.isEmpty
            ? 'Off — add something like vitamin D to tick off on Home'
            : items.map((i) => i.label).join(', '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ChecklistSettingsScreen(),
        ),
      ),
    );
  }
}

/// Choosing what is on the daily checklist, and in what order.
///
/// The list is the baby's, not this phone's: every caregiver sees the same
/// items. Each change is saved as it is made, with nothing to confirm.
class ChecklistSettingsScreen extends ConsumerStatefulWidget {
  const ChecklistSettingsScreen({super.key});

  @override
  ConsumerState<ChecklistSettingsScreen> createState() =>
      _ChecklistSettingsScreenState();
}

class _ChecklistSettingsScreenState
    extends ConsumerState<ChecklistSettingsScreen> {
  /// What is shown, ahead of the profile coming back with it: a dragged item
  /// has to land where it was dropped at once, not a frame later.
  List<ChecklistItem>? _items;

  void _save(Baby baby, List<ChecklistItem> items) {
    setState(() => _items = items);
    final repo = ref.read(babiesRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    // Not waited on, like every other write: offline it would not finish
    // until the phone reconnects, and the local cache has it already.
    unawaited(
      Future.sync(() => repo.updateChecklist(baby.id, items)).catchError((
        Object e,
      ) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save the checklist: $e')),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Someone else's change, arriving: it replaces what is shown.
    ref.listen(currentBabyProvider.select((b) => b?.checklist), (_, next) {
      if (next != null) setState(() => _items = next);
    });
    final baby = ref.watch(currentBabyProvider);
    final theme = Theme.of(context);

    if (baby == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Daily checklist')),
        body: const Center(child: Text('Add a baby first.')),
      );
    }
    final items = _items ?? baby.checklist;
    final full = items.length >= ChecklistItem.maxItems;
    final presets = [
      for (final p in checklistPresets)
        if (!items.any((i) => i.id == p.id)) p,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Daily checklist')),
      body: ReorderableListView(
        buildDefaultDragHandles: false,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Things to do once a day. They show on Home to tick off, and '
            'start fresh each morning. Everyone caring for ${baby.name} sees '
            'the same list.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        onReorderItem: (from, to) {
          final next = [...items];
          next.insert(to, next.removeAt(from));
          _save(baby, next);
        },
        footer: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (full)
                Text(
                  'That is the most the checklist holds.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in presets)
                      ActionChip(
                        key: ValueKey('add-${p.id}'),
                        avatar: Icon(checklistIcon(p.icon)),
                        label: Text(p.label),
                        onPressed: () => _save(baby, [...items, p]),
                      ),
                    ActionChip(
                      key: const ValueKey('add-own'),
                      avatar: const Icon(Icons.add),
                      label: const Text('Your own…'),
                      onPressed: () async {
                        final label = await _askLabel(context);
                        if (label == null || !mounted) return;
                        _save(baby, [
                          ...items,
                          ChecklistItem(
                            id: 'own-${DateTime.now().millisecondsSinceEpoch}',
                            label: label,
                          ),
                        ]);
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
        children: [
          for (final (i, item) in items.indexed)
            ListTile(
              key: ValueKey(item.id),
              leading: Icon(checklistIcon(item.icon)),
              title: Text(item.label),
              onTap: () async {
                final label = await _askLabel(context, initial: item.label);
                if (label == null || !mounted) return;
                // Same id, so the streak carries over to the new name.
                _save(baby, [
                  for (final it in items)
                    it.id == item.id
                        ? ChecklistItem(id: it.id, label: label, icon: it.icon)
                        : it,
                ]);
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Remove ${item.label}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _save(baby, [
                      for (final it in items)
                        if (it.id != item.id) it,
                    ]),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks for an item's name: blank or unchanged gives null.
Future<String?> _askLabel(BuildContext context, {String? initial}) async {
  final controller = TextEditingController(text: initial);
  final label = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(initial == null ? 'Add to the checklist' : 'Rename'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: ChecklistItem.maxLabel,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'e.g. Read a book'),
        onSubmitted: (v) => Navigator.pop(dialog, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, controller.text),
          child: Text(initial == null ? 'Add' : 'Save'),
        ),
      ],
    ),
  );
  // Not disposed here: the dialog is still animating out with the field in
  // it, and a disposed controller there throws. Nothing listens to it, so
  // it is collected with the dialog.
  final trimmed = label?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == initial) return null;
  return trimmed;
}
