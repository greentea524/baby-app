import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/models/baby.dart';
import '../../data/repositories/baby_data.dart';
import '../../data/repositories/repository_providers.dart';
import '../export/export_screen.dart';

/// Deleting a baby and everything logged under it (#28).
///
/// Deliberately a screen rather than a dialog. It has to say what is about to
/// go, offer the export first, and take a typed confirmation — a dialog that
/// does all three is a screen with a shadow under it.
class DeleteBabyScreen extends ConsumerStatefulWidget {
  const DeleteBabyScreen({super.key, required this.baby});

  final Baby baby;

  @override
  ConsumerState<DeleteBabyScreen> createState() => _DeleteBabyScreenState();
}

class _DeleteBabyScreenState extends ConsumerState<DeleteBabyScreen> {
  final _confirm = TextEditingController();

  Map<String, int>? _counts;
  String? _error;
  bool _deleting = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final counts = await ref
          .read(babyDataProvider)
          .countAll(widget.baby.id);
      if (mounted) setState(() => _counts = counts);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read what is stored: $e');
    }
  }

  bool get _nameMatches =>
      _confirm.text.trim().toLowerCase() == widget.baby.name.toLowerCase();

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
      _progress = 0;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(babyDataProvider)
          .deleteAll(
            widget.baby.id,
            onProgress: (n) {
              if (mounted) setState(() => _progress = n);
            },
          );
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.baby.name} and all of the '
            'logged entries were deleted.')),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        // Says what is still true, because the order guarantees it: nothing
        // is stranded and running it again resumes.
        _error = 'The delete stopped partway. Nothing is lost or unreachable '
            '— run it again to finish. ($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myUid = ref.watch(currentUidProvider);
    final isOwner = myUid != null && widget.baby.isOwner(myUid);

    return Scaffold(
      appBar: AppBar(title: Text('Delete ${widget.baby.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isOwner)
            _NotYours(name: widget.baby.name)
          else ...[
            _Summary(baby: widget.baby, counts: _counts),
            const SizedBox(height: 20),
            // Says why the button is there. A bare "Export" in front of a
            // delete is a button someone taps past; the reason to tap it is
            // that this is the only copy, and that is worth a sentence.
            Text(
              'This is the only copy — there is no undo, and nothing is kept '
              'anywhere else. If you want the record, export it first: a CSV '
              'log of every entry, or a PDF summary.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Before the confirmation rather than after it: a way out offered
            // once the decision is made is not much of an offer.
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
              'Type ${widget.baby.name} to confirm.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              enabled: !_deleting,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.baby.name,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            if (_deleting)
              _Progress(deleted: _progress)
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: _counts == null || !_nameMatches ? null : _delete,
                child: const Text('Delete permanently'),
              ),
          ],
        ],
      ),
    );
  }
}

/// What a non-owner is offered instead.
///
/// The asymmetry is not a UI convention — `firestore.rules` allows a member
/// to remove exactly themselves and nobody else, so offering Delete here
/// would be offering something the database refuses.
class _NotYours extends StatelessWidget {
  const _NotYours({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Only the caregiver who set $name up can delete the record. You can '
      'leave instead, which removes your access and leaves the data with '
      'everyone else.',
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.baby, required this.counts});

  final Baby baby;
  final Map<String, int>? counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = baby.memberUids.length - 1;

    if (counts == null) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Counting what is stored…'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Permanently delete ${BabyData.describe(counts!)}, along with '
          "${baby.name}'s profile.",
          style: theme.textTheme.titleMedium,
        ),
        if (others > 0) ...[
          const SizedBox(height: 12),
          Text(
            others == 1
                ? 'One other caregiver has access and will lose it too.'
                : '$others other caregivers have access and will lose it too.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.deleted});

  final int deleted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        // A count rather than a bar: the total is known but the work is a
        // series of round trips, and a bar that stalls reads as a hang.
        Text(deleted == 0 ? 'Deleting…' : 'Deleted $deleted…'),
      ],
    );
  }
}
