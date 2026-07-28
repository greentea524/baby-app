import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/repository_providers.dart';
import '../appointments/appointment_format.dart';
import '../diaper/diaper_format.dart';
import '../feeding/feeding_format.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';

/// The Home status card (KAN-179): where feeding, diapers, and the next
/// visit stand, in one place.
///
/// Feeding keeps its history and its prediction on a single row. They are the
/// same question asked twice — when did they last eat, and when is the next
/// one due — and splitting them across two cards meant scanning two places to
/// answer it.
class HomeStatusCard extends ConsumerWidget {
  const HomeStatusCard({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <Widget>[
      _feedingRow(context, ref),
      _diaperRow(context, ref),
      ?_appointmentRow(context, ref),
    ];

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  /// Last feed on top, next due underneath.
  Widget _feedingRow(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastFeedingProvider);
    final theme = Theme.of(context);

    final settings = ref.watch(reminderSettingsProvider);
    final due = settings.mode == ReminderMode.off
        ? null
        : ref.watch(feedPredictionProvider).nextDue;

    String? next;
    Color? nextColor;
    if (due != null) {
      final at = TimeOfDay.fromDateTime(due).format(context);
      final overdue = !due.isAfter(now);
      // "Next 2h overdue" reads badly, so the prefix is dropped once it has
      // slipped past.
      next = overdue
          ? '${countdownLabel(due, now: now)} · $at'
          : 'Next ${countdownLabel(due, now: now)} · $at';
      nextColor = overdue ? theme.colorScheme.error : null;
    }

    return _StatusRow(
      icon: last == null ? Icons.child_care : FeedingFormat.typeIcon(last.type),
      label: 'Last fed',
      value: last == null
          ? 'No feeds yet'
          : FeedingFormat.timeAgo(last.startTime, now: now),
      detail: last == null
          ? null
          : _join(
              FeedingFormat.clockStamp(context, last.startTime, now: now),
              _join(
                FeedingFormat.typeLabel(last.type),
                FeedingFormat.details(last),
              ),
            ),
      footer: next,
      footerColor: nextColor,
    );
  }

  Widget _diaperRow(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastDiaperProvider);
    return _StatusRow(
      icon: last == null
          ? Icons.baby_changing_station
          : DiaperFormat.typeIcon(last.type),
      label: 'Last changed',
      value: last == null
          ? 'No changes yet'
          : FeedingFormat.timeAgo(last.time, now: now),
      detail: last == null
          ? null
          : _join(
              FeedingFormat.clockStamp(context, last.time, now: now),
              _join(
                DiaperFormat.typeLabel(last.type),
                DiaperFormat.details(last),
              ),
            ),
    );
  }

  /// Null when nothing is scheduled — an empty row would be permanent clutter
  /// for anyone not using appointments.
  Widget? _appointmentRow(BuildContext context, WidgetRef ref) {
    final all = ref.watch(appointmentsProvider).value ?? const [];
    final upcoming = splitAppointments(all, now).upcoming;
    if (upcoming.isEmpty) return null;

    final next = upcoming.first;
    final theme = Theme.of(context);
    final imminent = AppointmentFormat.daysUntil(next.at, now: now) <= 1;
    final details = AppointmentFormat.details(next);
    final title = AppointmentFormat.title(next);

    return _StatusRow(
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

  static String _join(String label, String details) =>
      details.isEmpty ? label : '$label · $details';
}

/// One row: icon, label, headline value, a supporting detail, and an optional
/// footer that can carry its own colour (used for the next-feed countdown,
/// which turns red once overdue).
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.footer,
    this.footerColor,
    this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final String? footer;
  final Color? footerColor;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Captured so the null checks below read as plain conditions rather than
    // needing a bang operator on every use.
    final detailText = detail;
    final footerText = footer;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              icon,
              color: accent ?? theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(color: accent),
                ),
                if (detailText != null)
                  Text(
                    detailText,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (footerText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      footerText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: footerColor,
                        fontWeight: footerColor == null
                            ? null
                            : FontWeight.w600,
                      ),
                    ),
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
    return InkWell(onTap: onTap, child: content);
  }
}
