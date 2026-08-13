import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/caregiver_invite.dart';
import '../../data/repositories/repository_providers.dart';

/// Banner listing invitations addressed to the signed-in user, with
/// Accept / Decline actions (KAN-134). Renders nothing when there are none.
class IncomingInvitesBanner extends ConsumerWidget {
  const IncomingInvitesBanner({super.key});

  /// The same shape as `saveAndClose`, minus the close: the membership write
  /// is started but not awaited, because offline it would not complete and
  /// tapping Accept would appear to do nothing (#21). The local cache carries
  /// the new membership immediately, so switching to the baby is right away.
  void _accept(BuildContext context, WidgetRef ref, CaregiverInvite invite) {
    final repo = ref.read(babiesRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      Future.sync(() => repo.acceptInvite(invite)).catchError((Object e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not accept the invitation: $e')),
        );
      }),
    );
    unawaited(ref.read(selectedBabyIdProvider.notifier).select(invite.babyId));
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
