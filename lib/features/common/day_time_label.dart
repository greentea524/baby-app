import 'package:flutter/material.dart';

import '../timeline/timeline_format.dart';

/// The time, with the day under it (#29).
///
/// Shared because it started on the nursery screen and turned out to be worth
/// having on Home too — the app is often the thing already open at 3am, and
/// answering "what time is it" costs two lines.
///
/// The day comes from [TimelineFormat.weekdayDate] rather than `dayLabel`:
/// the latter collapses to "Today", which is the one thing a clock has no use
/// for.
class DayTimeLabel extends StatelessWidget {
  const DayTimeLabel({
    super.key,
    required this.clock,
    this.timeStyle,
    this.dayStyle,
  });

  final DateTime clock;

  /// Defaults suit the nursery header; Home passes something quieter.
  final TextStyle? timeStyle;
  final TextStyle? dayStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          TimeOfDay.fromDateTime(clock).format(context),
          style:
              timeStyle ??
              theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          maxLines: 1,
        ),
        Text(
          TimelineFormat.weekdayDate(clock),
          style:
              dayStyle ??
              theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
          maxLines: 1,
        ),
      ],
    );
  }
}
