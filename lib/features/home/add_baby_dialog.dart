import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/baby.dart';
import '../../data/repositories/repository_providers.dart';

/// Minimal baby-profile creation so feeding can be logged. Full profile
/// management (avatars, multiple babies, switching) is KAN-135.
Future<void> showAddBabyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AddBabyDialog(),
  );
}

class _AddBabyDialog extends ConsumerStatefulWidget {
  const _AddBabyDialog();

  @override
  ConsumerState<_AddBabyDialog> createState() => _AddBabyDialogState();
}

class _AddBabyDialogState extends ConsumerState<_AddBabyDialog> {
  final _nameController = TextEditingController();
  DateTime _birthDate = DateTime.now();
  BabySex? _sex;
  String? _nameError;
  bool _busy = false;

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
      await repo.addBaby(name: name, birthDate: _birthDate, sex: _sex);
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
      title: const Text('Add your baby'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
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
