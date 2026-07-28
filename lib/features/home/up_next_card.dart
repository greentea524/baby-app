import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/repository_providers.dart';
import '../appointments/appointment_format.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';

/// What's coming up: the predicted next feed and the next scheduled visit,
/// in one card (KAN-178).
///
/// These were separate cards, but they answer the same question — "what do I
/// need to be ready for?" — and Home was accumulating a stack of near
/// identical rectangles. Grouping them mirrors the summary card above, which
/// already pairs two related rows behind one divider.
///
/// Renders nothing when neither row has anything to say.
class UpNextCard extends ConsumerWidget {
  const UpNextCard({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = _feedRow(context, ref);
    final appointment = _appointmentRow(context, ref);
    if (feed == null && appointment == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          ?feed,
          // A real condition, not a null check: the divider only earns its
          // place when both rows are present.
          if (feed != null && appointment != null)
            const Divider(height: 1, indent: 16, endIndent: 16),
          ?appointment,
        ],
      ),
    );
  }

  /// The feed prediction row, or null when reminders are switched off.
  Widget? _feedRow(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    if (settings.mode == ReminderMode.off) return null;

    final prediction = ref.watch(feedPredictionProvider);
    final due = prediction.nextDue;
    final theme = Theme.of(context);

    if (due == null) {
      return _UpNextRow(
        icon: Icons.schedule,
        label: 'Next feed',
        value: 'Not enough history yet',
        detail: settings.mode == ReminderMode.predictive
            ? 'Log two feeds to start predicting.'
            : 'Log a feed to start the timer.',
      );
    }

    final overdue = !due.isAfter(now);
    return _UpNextRow(
      icon: overdue ? Icons.notifications_active : Icons.schedule,
      label: 'Next feed',
      value:
          '${countdownLabel(due, now: now)} · '
          '${TimeOfDay.fromDateTime(due).format(context)}',
      detail: settings.mode == ReminderMode.fixedInterval
          ? 'Every ${_hours(settings.intervalMinutes)}'
          : 'Avg ${_hours(prediction.averageIntervalMinutes ?? 0)} '
                'over ${prediction.intervalSamples} feeds',
      // Accent the row rather than the whole card: an overdue feed should not
      // recolour an appointment that is weeks away.
      accent: overdue ? theme.colorScheme.error : null,
    );
  }

  /// The next scheduled visit, or null when nothing is upcoming.
  Widget? _appointmentRow(BuildContext context, WidgetRef ref) {
    final all = ref.watch(appointmentsProvider).value ?? const [];
    final upcoming = splitAppointments(all, now).upcoming;
    if (upcoming.isEmpty) return null;

    final next = upcoming.first;
    final theme = Theme.of(context);
    final imminent = AppointmentFormat.daysUntil(next.at, now: now) <= 1;
    final details = AppointmentFormat.details(next);
    final title = AppointmentFormat.title(next);

    return _UpNextRow(
      icon: AppointmentFormat.kindIcon(next.kind),
      label: 'Next appointment',
      value:
          '${AppointmentFormat.countdown(next.at, now: now)} · '
          '${TimeOfDay.fromDateTime(next.at).format(context)}',
      detail: details.isEmpty ? title : '$title · $details',
      accent: imminent ? theme.colorScheme.tertiary : null,
      onTap: () => context.go(AppRoutes.appointments),
    );
  }

  static String _hours(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

/// One line of the card: icon, label, headline value, and a supporting
/// detail. Tappable rows get a chevron so it's clear they lead somewhere.
class _UpNextRow extends StatelessWidget {
  const _UpNextRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  /// Highlight colour for an overdue feed or an imminent visit.
  final Color? accent;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(color: accent),
                ),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}
