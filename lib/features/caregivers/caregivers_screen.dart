import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/baby.dart';
import '../../data/models/caregiver_invite.dart';
import '../../data/repositories/repository_providers.dart';
import '../../core/auth/auth_providers.dart';
import 'invite_message.dart';

/// Manage who can log for the current baby (KAN-134): view caregivers,
/// add them by email, revoke pending invites, and remove members.
///
/// Adding a caregiver only writes an invite document — nothing is delivered to
/// them (#10). The wording here says so, and the copy action gives the sender a
/// ready-made message to pass on themselves.
class CaregiversScreen extends ConsumerWidget {
  const CaregiversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(currentBabyProvider);
    final myUid = ref.watch(authStateProvider).value?.uid;
    final invitesAsync = ref.watch(currentBabyInvitesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Caregivers')),
      body: baby == null || myUid == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a baby on the Home tab first.'),
              ),
            )
          : ListView(
              children: [
                const _SectionHeader('Caregivers'),
                for (final entry in baby.members.entries)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(
                      entry.key == myUid ? 'You' : _shortUid(entry.key),
                    ),
                    subtitle: Text(entry.value.name),
                    trailing: _memberAction(
                      context,
                      ref,
                      baby,
                      myUid,
                      entry.key,
                    ),
                  ),
                const Divider(),
                const _SectionHeader('Pending invites'),
                invitesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Could not load invites: $e'),
                  ),
                  data: (invites) => invites.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text('No pending invites.'),
                        )
                      : Column(
                          children: [
                            for (final invite in invites)
                              PendingInviteTile(
                                invite: invite,
                                // Revoking is a roster change, so it stays with
                                // the owner. Copying only repeats the address
                                // already on this row, so any member may.
                                canRevoke: baby.isOwner(myUid),
                                onCopy: () => _copyInviteMessage(
                                  context,
                                  babyName: baby.name,
                                  email: invite.email,
                                ),
                                onRevoke: () => ref
                                    .read(babiesRepositoryProvider)
                                    ?.revokeInvite(baby.id, invite.email),
                              ),
                          ],
                        ),
                ),
                const Divider(),
                if (baby.isOwner(myUid))
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: () => _showInvite(context, ref, baby),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add caregiver'),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      onPressed: () => _leave(context, ref, baby),
                      icon: const Icon(Icons.logout),
                      label: Text('Leave ${baby.name}'),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget? _memberAction(
    BuildContext context,
    WidgetRef ref,
    Baby baby,
    String myUid,
    String memberUid,
  ) {
    if (memberUid == baby.ownerUid) {
      return const Chip(label: Text('Owner'));
    }
    if (!baby.isOwner(myUid)) return null;
    return IconButton(
      icon: const Icon(Icons.remove_circle_outline),
      tooltip: 'Remove',
      onPressed: () =>
          ref.read(babiesRepositoryProvider)?.removeMember(baby.id, memberUid),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Baby baby) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${baby.name}?'),
        content: const Text('You will no longer see this baby.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(babiesRepositoryProvider)?.leaveBaby(baby.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  static String _shortUid(String uid) =>
      uid.length <= 6 ? uid : 'User ${uid.substring(0, 6)}';
}

Future<void> _showInvite(BuildContext context, WidgetRef ref, Baby baby) {
  return showDialog<void>(
    context: context,
    builder: (_) => _InviteDialog(baby: baby),
  );
}

/// Puts the hand-off message on the clipboard and says so.
Future<void> _copyInviteMessage(
  BuildContext context, {
  required String babyName,
  required String email,
}) async {
  await Clipboard.setData(
    ClipboardData(
      text: inviteShareMessage(
        babyName: babyName,
        email: email,
        appUrl: currentAppUrl(),
      ),
    ),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Message copied — send it to them')),
  );
}

/// One pending invite: who it is for, that it is still waiting, and the two
/// things you can do about it.
///
/// Split out of [CaregiversScreen] so it can be widget-tested — the screen
/// itself needs a signed-in Firebase session and a selected baby.
class PendingInviteTile extends StatelessWidget {
  const PendingInviteTile({
    super.key,
    required this.invite,
    required this.canRevoke,
    required this.onCopy,
    required this.onRevoke,
  });

  final CaregiverInvite invite;

  /// Revoking removes someone from the roster, so it is the owner's to do.
  final bool canRevoke;

  final VoidCallback onCopy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      // Not a mail icon: nothing was posted, and this is waiting rather than
      // in flight.
      leading: const Icon(Icons.hourglass_empty),
      title: Text(invite.email),
      subtitle: Text('${invite.role.name} · waiting for them to sign in'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy message to send',
            onPressed: onCopy,
          ),
          if (canRevoke)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Revoke',
              onPressed: onRevoke,
            ),
        ],
      ),
    );
  }
}

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.baby});

  final Baby baby;

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  final _controller = TextEditingController();
  CaregiverRole _role = CaregiverRole.editor;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _add() async {
    final email = _controller.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(babiesRepositoryProvider)
          ?.inviteCaregiver(
            babyId: widget.baby.id,
            babyName: widget.baby.name,
            email: email,
            role: _role,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      // The moment the sender is about to message them is right now, so offer
      // the text here rather than leaving it to be found on the row later.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$email added. They will not be notified — tell them.'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Copy message',
            onPressed: () => _copyInviteMessage(
              context,
              babyName: widget.baby.name,
              email: email,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not add: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add caregiver'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              errorText: _error,
              helperText:
                  'No email is sent — you tell them. They must sign in with '
                  'this exact address.',
              helperMaxLines: 3,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 16),
          SegmentedButton<CaregiverRole>(
            segments: const [
              ButtonSegment(value: CaregiverRole.editor, label: Text('Editor')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _add,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
