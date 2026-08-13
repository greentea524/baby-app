import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/baby.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/save_and_close.dart';

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
  late BabyAvatar _avatar = widget.existing?.avatar ?? BabyAvatar.baby;
  String? _nameError;

  /// Guards against a second tap landing while the dialog is closing. There
  /// is no spinner any more — it goes immediately (#21) — so this is all that
  /// stands between an impatient double-tap and two babies.
  bool _saving = false;

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

  void _save() {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    final repo = ref.read(babiesRepositoryProvider);
    if (repo == null) return;
    _saving = true;

    if (_isEdit) {
      final edited = widget.existing!.copyWith(
        name: name,
        birthDate: _birthDate,
        sex: _sex,
        avatar: _avatar,
      );
      saveAndClose(
        context,
        () => repo.updateBaby(edited),
        failure: 'Could not save the baby',
      );
      return;
    }

    final created = repo.addBaby(
      name: name,
      birthDate: _birthDate,
      sex: _sex,
      avatar: _avatar,
    );
    // The id exists before the write does, so the new baby can be selected
    // straight away — which is what makes the rest of the app show it while
    // the write is still queued.
    unawaited(ref.read(selectedBabyIdProvider.notifier).select(created.id));
    saveAndClose(
      context,
      () => created.written,
      failure: 'Could not save the baby',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit baby' : 'Add your baby'),
      // Fixed width so the avatar grid wraps instead of stretching the
      // dialog, and scrollable so it survives a short/landscape window.
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Avatar',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(height: 8),
              _AvatarPicker(
                selected: _avatar,
                onSelected: (a) => setState(() => _avatar = a),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// The avatar choices as tappable circles, the selected one ringed in the
/// primary colour. Each carries a [Semantics] label because an emoji on its
/// own reads poorly to a screen reader.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.selected, required this.onSelected});

  final BabyAvatar selected;
  final ValueChanged<BabyAvatar> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final avatar in BabyAvatar.values)
          Semantics(
            label: avatar.label,
            button: true,
            selected: avatar == selected,
            child: InkWell(
              onTap: () => onSelected(avatar),
              customBorder: const CircleBorder(),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatar == selected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  border: avatar == selected
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                child: Text(avatar.emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
          ),
      ],
    );
  }
}
