import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'feed_prediction.dart';
import 'reminder_providers.dart';

/// Home card showing when the next feed is due, with a live countdown that
/// turns to an overdue state once the time passes (KAN-133).
///
/// This is the in-app reminder. Background notifications while the app is
/// closed need FCM + a service worker + a scheduled Cloud Function; see
/// KAN-156.
class NextFeedCard extends ConsumerWidget {
  const NextFeedCard({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    if (settings.mode == ReminderMode.off) return const SizedBox.shrink();

    final prediction = ref.watch(feedPredictionProvider);
    final due = prediction.nextDue;
    final theme = Theme.of(context);

    if (due == null) {
      return _shell(
        context,
        icon: Icons.schedule,
        title: 'Next feed',
        value: 'Not enough history yet',
        detail: settings.mode == ReminderMode.predictive
            ? 'Log two feeds to start predicting.'
            : 'Log a feed to start the timer.',
        overdue: false,
      );
    }

    final overdue = !due.isAfter(now);
    final at = TimeOfDay.fromDateTime(due).format(context);
    final basis = settings.mode == ReminderMode.fixedInterval
        ? 'Every ${_hours(settings.intervalMinutes)}'
        : 'Avg ${_hours(prediction.averageIntervalMinutes ?? 0)} '
              'over ${prediction.intervalSamples} feeds';

    return _shell(
      context,
      icon: overdue ? Icons.notifications_active : Icons.schedule,
      title: 'Next feed',
      value: '${countdownLabel(due, now: now)} · $at',
      detail: basis,
      overdue: overdue,
      color: overdue ? theme.colorScheme.error : null,
    );
  }

  Widget _shell(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required String detail,
    required bool overdue,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: overdue ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: accent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelMedium),
                  Text(value, style: theme.textTheme.titleMedium),
                  Text(detail, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _hours(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
