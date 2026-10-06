import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/models/medication_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/app_sheet.dart';
import '../common/event_time_row.dart';
import '../common/number_input.dart';
import '../common/save_and_close.dart';

/// Opens the medicine sheet (#37). Pass [existing] to edit a dose.
Future<void> showMedicationQuickLog(
  BuildContext context, {
  MedicationEvent? existing,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _MedicationSheet(existing: existing),
  );
}

/// The longest name the rules accept.
const int medicineNameMax = 60;

/// The medicines this baby has had, most recent first, each with the dose
/// it was last given at — at most [limit] of them.
///
/// Learned from the log rather than built in: the app knows no medicines,
/// and offering one it was never told about would be a suggestion to give
/// it. Names are matched without regard to case or spacing, so "tylenol"
/// and "Tylenol " are one medicine, shown as it was last written.
List<MedicationEvent> recentMedicines(
  List<MedicationEvent> doses, {
  int limit = 4,
}) {
  final seen = <String>{};
  final out = <MedicationEvent>[];
  final sorted = [...doses]..sort((a, b) => b.time.compareTo(a.time));
  for (final d in sorted) {
    if (seen.add(d.name.trim().toLowerCase())) out.add(d);
    if (out.length == limit) break;
  }
  return out;
}

class _MedicationSheet extends ConsumerStatefulWidget {
  const _MedicationSheet({this.existing});

  final MedicationEvent? existing;

  @override
  ConsumerState<_MedicationSheet> createState() => _MedicationSheetState();
}

class _MedicationSheetState extends ConsumerState<_MedicationSheet> {
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _time;
  DoseUnit _unit = DoseUnit.ml;

  /// Guards a second tap landing while the sheet closes (#21).
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _time = e?.time ?? DateTime.now();
    if (e != null) {
      _name.text = e.name;
      if (e.dose != null) _dose.text = _number(e.dose!);
      _unit = e.unit ?? DoseUnit.ml;
      if (e.notes != null) _notes.text = e.notes!;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String _number(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toString();

  /// Fills in a medicine given before: its name, and the dose and unit it
  /// was last given at, to correct if today's is different.
  void _useRecent(MedicationEvent last) => setState(() {
    _name.text = last.name;
    _dose.text = last.dose == null ? '' : _number(last.dose!);
    _unit = last.unit ?? _unit;
  });

  double? get _doseValue {
    final text = _dose.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  /// Whether what is typed can be saved: a name, and a dose that is either
  /// left empty or a number above zero.
  bool get _valid {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > medicineNameMax) return false;
    final text = _dose.text.trim();
    if (text.isEmpty) return true;
    final dose = double.tryParse(text);
    return dose != null && dose > 0;
  }

  void _save() {
    if (_saving || !_valid) return;
    final repo = ref.read(medicationRepositoryProvider);
    if (repo == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No baby selected.')));
      return;
    }
    final existing = widget.existing;
    final user = ref.read(authStateProvider).value;
    final dose = _doseValue;
    final event = MedicationEvent(
      id: existing?.id ?? '',
      time: _time,
      name: _name.text.trim(),
      dose: dose,
      unit: dose == null ? null : _unit,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      // Who gave it is who logged it first; an edit keeps that.
      byName: existing != null
          ? existing.byName
          : (user?.displayName?.trim().isNotEmpty ?? false)
          ? user!.displayName!.trim()
          : user?.email?.split('@').first,
    );
    _saving = true;
    saveAndClose(
      context,
      () => existing != null ? repo.update(event) : repo.add(event),
      failure: 'Could not save the medicine',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    final recent = recentMedicines(ref.watch(recentMedsProvider).value ?? []);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isEdit ? 'Edit medicine' : 'Log medicine',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: !isEdit && recent.isEmpty,
          textCapitalization: TextCapitalization.words,
          maxLength: medicineNameMax,
          decoration: const InputDecoration(
            labelText: 'Medicine',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        // What has been given before, so the usual one is a tap: name and
        // last dose together.
        if (!isEdit && recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in recent)
                  ActionChip(
                    avatar: const Icon(Icons.history, size: 18),
                    label: Text(m.name),
                    onPressed: () => _useRecent(m),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _dose,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: positiveDecimalInput,
          decoration: InputDecoration(
            labelText: 'Dose (optional)',
            suffixText: _unit.plural,
            border: const OutlineInputBorder(),
            errorText: _dose.text.trim().isNotEmpty && !_valid
                ? 'A number above zero'
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final u in DoseUnit.values)
              ChoiceChip(
                label: Text(u.plural),
                selected: _unit == u,
                // The fill says which is chosen; a tick as well widened the
                // five past one line on a phone.
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _unit = u),
              ),
          ],
        ),
        const SizedBox(height: 12),
        EventTimeRow(time: _time, onChanged: (t) => setState(() => _time = t)),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        // Said once, plainly: this is a record, not advice.
        Text(
          'Record what was given. Follow the label or your doctor for how '
          'much and how often.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _valid && !isFutureLogTime(_time) ? _save : null,
          child: Text(isEdit ? 'Save changes' : 'Save'),
        ),
      ],
    );
  }
}
