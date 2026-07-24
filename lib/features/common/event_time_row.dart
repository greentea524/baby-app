import 'package:flutter/material.dart';

/// A row showing an event's time with a button to change it (date + time).
/// Shared by the feeding and diaper quick-log forms.
class EventTimeRow extends StatelessWidget {
  const EventTimeRow({super.key, required this.time, required this.onChanged});

  final DateTime time;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pick(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: time,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(time),
    );
    if (t == null) return;
    onChanged(DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final local = TimeOfDay.fromDateTime(time).format(context);
    return Row(
      children: [
        const Icon(Icons.schedule, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('$local · ${time.month}/${time.day}')),
        TextButton(
          onPressed: () => _pick(context),
          child: const Text('Change'),
        ),
      ],
    );
  }
}
