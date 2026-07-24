import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/baby.dart';
import '../../data/repositories/repository_providers.dart';

/// Create a baby (and auto-select it), or edit an existing one when
/// [existing] is passed (KAN-135).
Future<void> showBabyDialog(BuildContext context, {Baby? existing}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BabyDialog(existing: existing),
  );
}

/// Back-compat entry point used by the home "no baby yet" prompt.
Future<void> showAddBabyDialog(BuildContext context) => showBabyDialog(context);

class _BabyDialog extends ConsumerStatefulWidget {
  const _BabyDialog({this.existing});

  final Baby? existing;

  @override
  ConsumerState<_BabyDialog> createState() => _BabyDialogState();
}

class _BabyDialogState extends ConsumerState<_BabyDialog> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late DateTime _birthDate = widget.existing?.birthDate ?? DateTime.now();
  late BabySex? _sex = widget.existing?.sex;
  String? _nameError;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    final repo = ref.read(babiesRepositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      if (_isEdit) {
        await repo.updateBaby(
          widget.existing!.copyWith(
            name: name,
            birthDate: _birthDate,
            sex: _sex,
          ),
        );
      } else {
        final id = await repo.addBaby(
          name: name,
          birthDate: _birthDate,
          sex: _sex,
        );
        await ref.read(selectedBabyIdProvider.notifier).select(id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit baby' : 'Add your baby'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _nameError,
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.cake_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Born ${_birthDate.month}/${_birthDate.day}/${_birthDate.year}',
                ),
              ),
              TextButton(onPressed: _pickDate, child: const Text('Change')),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Sex (for growth percentiles)',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 4),
          SegmentedButton<BabySex?>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: BabySex.male, label: Text('Male')),
              ButtonSegment(value: BabySex.female, label: Text('Female')),
            ],
            selected: {_sex},
            onSelectionChanged: (s) =>
                setState(() => _sex = s.isEmpty ? null : s.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
