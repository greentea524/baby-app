import 'package:flutter/material.dart';

/// A row showing an event's time, with separate buttons for changing the time
/// and the date. Shared by the feeding, diaper, and pumping quick-log forms.
///
/// Two buttons rather than one chained flow: almost everything is logged on
/// the day it happens, so pairing the two pickers meant always answering the
/// question you did not have in order to reach the one you did — in either
/// order.
class EventTimeRow extends StatelessWidget {
  const EventTimeRow({super.key, required this.time, required this.onChanged});

  final DateTime time;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(time),
    );
    if (picked == null) return;
    // Keeps the day, changes the clock.
    onChanged(
      DateTime(time.year, time.month, time.day, picked.hour, picked.minute),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: time,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    // Keeps the clock, changes the day.
    onChanged(
      DateTime(picked.year, picked.month, picked.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = TimeOfDay.fromDateTime(time).format(context);
    return Row(
      children: [
        const Icon(Icons.schedule, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('${time.month}/${time.day} · $local')),
        TextButton(
          onPressed: () => _pickDate(context),
          child: const Text('Date'),
        ),
        TextButton(
          onPressed: () => _pickTime(context),
          child: const Text('Time'),
        ),
      ],
    );
  }
}
