import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/baby.dart';
import '../../data/repositories/repository_providers.dart';
import 'add_baby_dialog.dart';
import 'baby_age.dart';

/// App-bar title showing the current baby with a tap target to switch
/// between profiles (KAN-135).
class BabySwitcher extends ConsumerWidget {
  const BabySwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(currentBabyProvider);
    final babies = ref.watch(babiesStreamProvider).value ?? const [];
    final canSwitch = babies.length > 1;

    return InkWell(
      onTap: () => _showBabyPicker(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (baby != null) ...[
              Text(baby.avatar.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
            ],
            // The age goes under the name rather than beside it: the app bar
            // already shares its width with the companion and the next
            // appointment, and a second line costs none of it.
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baby?.name ?? 'Home',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (baby != null)
                    Text(
                      babyAgeLabel(baby.birthDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              canSwitch ? Icons.arrow_drop_down : Icons.expand_more,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showBabyPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _BabyPickerSheet(),
  );
}

class _BabyPickerSheet extends ConsumerWidget {
  const _BabyPickerSheet();

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Baby baby,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${baby.name}?'),
        content: const Text(
          'The profile is removed. Logged entries are no longer shown.',
        ),
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
    if (ok == true) {
      await ref.read(babiesRepositoryProvider)?.deleteBaby(baby.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final babies = ref.watch(babiesStreamProvider).value ?? const [];
    final current = ref.watch(currentBabyProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Babies',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final baby in babies)
            ListTile(
              leading: CircleAvatar(
                child: Text(
                  baby.avatar.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              title: Text(baby.name),
              subtitle: Text(
                '${babyAgeLabel(baby.birthDate)} · born '
                '${baby.birthDate.month}/${baby.birthDate.day}/'
                '${baby.birthDate.year}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (baby.id == current?.id)
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') {
                        showBabyDialog(context, existing: baby);
                      } else if (v == 'delete') {
                        _confirmDelete(context, ref, baby);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              onTap: () {
                ref.read(selectedBabyIdProvider.notifier).select(baby.id);
                Navigator.of(context).pop();
              },
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add baby'),
            onTap: () {
              Navigator.of(context).pop();
              showBabyDialog(context);
            },
          ),
        ],
      ),
    );
  }
}
