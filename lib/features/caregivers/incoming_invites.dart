import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/caregiver_invite.dart';
import '../../data/repositories/repository_providers.dart';

/// Banner listing invitations addressed to the signed-in user, with
/// Accept / Decline actions (KAN-134). Renders nothing when there are none.
class IncomingInvitesBanner extends ConsumerWidget {
  const IncomingInvitesBanner({super.key});

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    CaregiverInvite invite,
  ) async {
    final repo = ref.read(babiesRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.acceptInvite(invite);
      await ref.read(selectedBabyIdProvider.notifier).select(invite.babyId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not accept: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(incomingInvitesProvider).value ?? const [];
    if (invites.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      children: [
        for (final invite in invites)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You\'re invited to help track ${invite.babyName}.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => ref
                            .read(babiesRepositoryProvider)
                            ?.declineInvite(invite),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _accept(context, ref, invite),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
