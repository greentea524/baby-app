import 'package:flutter/material.dart';

/// Whether [time] is ahead of the clock, and so cannot describe something that
/// has already happened.
///
/// Shared by [EventTimeRow] and the forms around it, so the row's warning and
/// the disabled save button never disagree about what counts as future.
bool isFutureLogTime(DateTime time, {DateTime? now}) =>
    time.isAfter(now ?? DateTime.now());

/// A row showing an event's time, with separate buttons for changing the time
/// and the date. Shared by the feeding, diaper, and pumping quick-log forms.
///
/// Two buttons rather than one chained flow: almost everything is logged on
/// the day it happens, so pairing the two pickers meant always answering the
/// question you did not have in order to reach the one you did — in either
/// order.
///
/// Future times are refused. Every form using this row logs something that
/// already happened, and a time stamped ahead of the clock breaks more than
/// its own record: "last fed" sticks at "just now" until the clock catches up,
/// the next feed is predicted from a feed nobody has given, and the day's
/// totals land on the wrong day.
class EventTimeRow extends StatefulWidget {
  const EventTimeRow({super.key, required this.time, required this.onChanged});

  final DateTime time;
  final ValueChanged<DateTime> onChanged;

  @override
  State<EventTimeRow> createState() => _EventTimeRowState();
}

class _EventTimeRowState extends State<EventTimeRow> {
  /// Set when a pick was refused, so the row can say why nothing changed.
  /// Without it, a refusal is indistinguishable from a tap that missed.
  bool _refused = false;

  /// Applies [candidate], or refuses it for being ahead of the clock.
  void _offer(DateTime candidate) {
    if (isFutureLogTime(candidate)) {
      setState(() => _refused = true);
      return;
    }
    setState(() => _refused = false);
    widget.onChanged(candidate);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(widget.time),
    );
    if (picked == null) return;
    // Keeps the day, changes the clock. showTimePicker takes no bounds, so
    // this is the only place a time can be checked.
    final t = widget.time;
    _offer(DateTime(t.year, t.month, t.day, picked.hour, picked.minute));
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // A record already stamped ahead would put initialDate past lastDate,
      // which showDatePicker asserts on rather than clamping.
      initialDate: widget.time.isAfter(now) ? now : widget.time,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null) return;
    // Keeps the clock, changes the day. Today is selectable, so this can
    // still land ahead of the clock — an evening time on today's date.
    final t = widget.time;
    _offer(DateTime(picked.year, picked.month, picked.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = TimeOfDay.fromDateTime(widget.time).format(context);
    // Shown for a refused pick, and for a record already stamped ahead —
    // editing one of those is the only way a future time can still be sitting
    // here, and it should be visible rather than only disabling the save.
    final warn = _refused || isFutureLogTime(widget.time);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${widget.time.month}/${widget.time.day} · $local'),
            ),
            TextButton(
              onPressed: () => _pickDate(context),
              child: const Text('Date'),
            ),
            TextButton(
              onPressed: () => _pickTime(context),
              child: const Text('Time'),
            ),
          ],
        ),
        if (warn)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 2),
            child: Text(
              "That's in the future — pick a time that has already happened.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
