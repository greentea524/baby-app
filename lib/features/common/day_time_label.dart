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
    this.timeHeight,
  });

  final DateTime clock;

  /// Defaults suit a header; Home passes something quieter.
  final TextStyle? timeStyle;
  final TextStyle? dayStyle;

  /// Draws the time this tall, scaled to fit, instead of at its text size.
  ///
  /// For nursery mode, where the point is to be legible from a doorway.
  /// Fixing the *height* rather than the width is what keeps it steady: a
  /// clock sized to fill its width would visibly change size at 9:59, when
  /// "9:59 AM" becomes "10:00 AM" and the string gains a digit.
  final double? timeHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final time = Text(
      TimeOfDay.fromDateTime(clock).format(context),
      style:
          timeStyle ??
          theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      maxLines: 1,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (timeHeight case final h?)
          SizedBox(
            height: h,
            child: FittedBox(child: time),
          )
        else
          time,
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
