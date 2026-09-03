import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/models/baby.dart';
import '../../data/repositories/account_data.dart';
import '../../data/repositories/repository_providers.dart';
import '../export/export_screen.dart';

/// Deleting the account and everything it owns (#28, scope B).
///
/// Deleting one baby took nearly all the volume and almost none of the
/// identity — the email address stayed in two places. This is the half that
/// makes "delete my data" true.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();

  String? _error;
  String? _step;
  bool _deleting = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool _matches(String email) =>
      _confirm.text.trim().toLowerCase() == email.trim().toLowerCase();

  Future<void> _delete(String uid, String email, List<Baby> babies) async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);

    try {
      // First, before anything is destroyed. On a mobile browser this
      // redirects away and comes back — done here that costs a second tap,
      // done in the middle it would abandon a half-finished deletion.
      setState(() => _step = 'Confirming it is you…');
      await auth.reauthenticate();

      setState(() => _step = 'Deleting your records…');
      await ref
          .read(accountDataProvider)
          .deleteAll(uid: uid, email: email, babies: babies);

      setState(() => _step = 'Closing the account…');
      await auth.deleteAccount();

      // The local copy outlives the account otherwise: Firestore keeps a
      // cache in IndexedDB and signing out does not clear it.
      await FirebaseFirestore.instance.terminate();
      await FirebaseFirestore.instance.clearPersistence();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _step = null;
        _error = e.code == 'requires-recent-login'
            ? 'Signing in again did not complete. Try once more.'
            : 'Could not finish: ${e.message ?? e.code} [${e.code}]';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _step = null;
        // Ordering makes this safe to repeat: records go before the account,
        // so nothing is stranded and running it again resumes.
        _error =
            'The deletion stopped partway. Nothing is left unreachable '
            '— run it again to finish. ($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);
    final email = ref.watch(authStateProvider).value?.email;
    final babies = ref.watch(babiesStreamProvider).value ?? const <Baby>[];

    if (uid == null || email == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delete account')),
        body: const Center(child: Text('Not signed in.')),
      );
    }

    final parts = AccountData.split(babies, uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Permanently delete $email and everything stored under it.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _WhatGoes(owned: parts.owned, shared: parts.shared),
          const SizedBox(height: 20),
          Text(
            'This is the only copy — there is no undo, and nothing is kept '
            'anywhere else. If you want the record, export it first: a CSV '
            'log of every entry, or a PDF summary.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.ios_share),
            label: const Text('Export the data first'),
            onPressed: _deleting
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExportScreen(),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          Text(
            'You will be asked to sign in again first — deleting an account '
            'needs a fresh sign-in.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text('Type $email to confirm.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _confirm,
            enabled: !_deleting,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Your email address',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          if (_deleting)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(_step ?? 'Deleting…'),
              ],
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: _matches(email)
                  ? () => _delete(uid, email, babies)
                  : null,
              child: const Text('Delete account permanently'),
            ),
        ],
      ),
    );
  }
}

/// Spelled out, because "your account" hides what is actually in it.
class _WhatGoes extends StatelessWidget {
  const _WhatGoes({required this.owned, required this.shared});

  final List<Baby> owned;
  final List<Baby> shared;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final baby in owned)
          _Line(
            icon: Icons.delete_forever_outlined,
            text: '${baby.name} and every entry logged for them',
          ),
        // Left, not deleted: that data belongs to whoever else is on it.
        for (final baby in shared)
          _Line(
            icon: Icons.logout,
            text:
                'You leave ${baby.name}. Their records stay with the '
                'others on it.',
          ),
        const _Line(
          icon: Icons.notifications_off_outlined,
          text: 'Your reminder settings and push notifications',
        ),
        const _Line(
          icon: Icons.mail_outline,
          text:
              'Your address, from the invitation list. Getting back in '
              'would mean someone adding it again by hand.',
        ),
        const _Line(
          icon: Icons.person_off_outlined,
          text: 'Your sign-in itself',
        ),
        const SizedBox(height: 4),
        Text(
          'The copy cached on this device goes too.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
