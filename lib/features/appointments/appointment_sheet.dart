import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/appointment.dart';
import '../../data/repositories/repository_providers.dart';
import 'appointment_format.dart';

/// Opens the appointment sheet. Pass [existing] to edit.
Future<void> showAppointmentSheet(
  BuildContext context, {
  Appointment? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _AppointmentSheet(existing: existing),
    ),
  );
}

class _AppointmentSheet extends ConsumerStatefulWidget {
  const _AppointmentSheet({this.existing});

  final Appointment? existing;

  @override
  ConsumerState<_AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends ConsumerState<_AppointmentSheet> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _provider = TextEditingController(
    text: widget.existing?.provider ?? '',
  );
  late final _location = TextEditingController(
    text: widget.existing?.location ?? '',
  );
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');

  late DateTime _at = widget.existing?.at ?? _defaultWhen();
  late AppointmentKind _kind = widget.existing?.kind ?? AppointmentKind.checkup;
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  /// New appointments default to 10:00 AM a week out — appointments are
  /// scheduled ahead, so "now" is almost never the answer.
  static DateTime _defaultWhen() {
    final week = DateTime.now().add(const Duration(days: 7));
    return DateTime(week.year, week.month, week.day, 10);
  }

  @override
  void dispose() {
    _title.dispose();
    _provider.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      // Past dates stay reachable so a visit can be logged after the fact.
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked == null) return;
    setState(() {
      _at = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _at.hour,
        _at.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (picked == null) return;
    setState(() {
      _at = DateTime(_at.year, _at.month, _at.day, picked.hour, picked.minute);
    });
  }

  String? _trimmed(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    final repo = ref.read(appointmentsRepositoryProvider);
    if (repo == null) {
      setState(() => _error = 'No baby selected.');
      return;
    }
    final appointment = Appointment(
      id: widget.existing?.id ?? '',
      at: _at,
      kind: _kind,
      title: _trimmed(_title),
      provider: _trimmed(_provider),
      location: _trimmed(_location),
      notes: _trimmed(_notes),
      completedAt: widget.existing?.completedAt,
    );
    setState(() => _busy = true);
    try {
      if (_isEdit) {
        await repo.update(appointment);
      } else {
        await repo.add(appointment);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit ? 'Edit appointment' : 'New appointment',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AppointmentKind>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final k in AppointmentKind.values)
                    DropdownMenuItem(
                      value: k,
                      child: Row(
                        children: [
                          Icon(AppointmentFormat.kindIcon(k), size: 18),
                          const SizedBox(width: 8),
                          Text(AppointmentFormat.kindLabel(k)),
                        ],
                      ),
                    ),
                ],
                onChanged: (k) {
                  if (k != null) setState(() => _kind = k);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event, size: 18),
                      label: Text('${_at.month}/${_at.day}/${_at.year}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(TimeOfDay.fromDateTime(_at).format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(_title, 'Title', hint: 'e.g. 6-month well visit'),
              const SizedBox(height: 12),
              _field(_provider, 'Doctor or clinic'),
              const SizedBox(height: 12),
              _field(_location, 'Location'),
              const SizedBox(height: 12),
              _field(_notes, 'Notes', maxLines: 2),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? 'Save changes' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
    );
  }
}
