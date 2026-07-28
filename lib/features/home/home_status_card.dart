import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../data/repositories/repository_providers.dart';
import '../appointments/appointment_format.dart';
import '../diaper/diaper_format.dart';
import '../feeding/feeding_format.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';
import '../timeline/timeline_format.dart';
import 'home_prefs.dart';

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
    // Feeding and diapers sit side by side: they are the two things you check
    // constantly, and stacking them pushed the second one down the screen.
    // The next-feed chip spans both columns because its text is too long to
    // live in half a card.
    final rows = <Widget>[
      _lastPair(context, ref),
      ?_appointmentRow(context, ref),
    ];

    if (ref.watch(homeLayoutProvider) == HomeLayout.separate) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          children: [
            for (final row in rows)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: row,
                ),
              ),
          ],
        ),
      );
    }

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

  /// Last feed and last diaper change, in two columns, with the next-feed
  /// countdown underneath spanning both.
  Widget _lastPair(BuildContext context, WidgetRef ref) {
    final chip = _nextFeedChip(context, ref);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _feedingHalf(context, ref)),
                const VerticalDivider(width: 24, thickness: 1),
                Expanded(child: _diaperHalf(context, ref)),
              ],
            ),
          ),
          ?chip,
        ],
      ),
    );
  }

  Widget _feedingHalf(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastFeedingProvider);
    final units = ref.watch(unitSystemProvider);
    return _HalfStat(
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
                FeedingFormat.details(last, units),
              ),
            ),
    );
  }

  Widget _diaperHalf(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastDiaperProvider);
    return _HalfStat(
      icon: last == null
          ? Icons.baby_changing_station
          : DiaperFormat.typeIcon(last.type),
      label: 'Last diaper',
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

  /// Null when reminders are off or there isn't enough history to predict.
  Widget? _nextFeedChip(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    if (settings.mode == ReminderMode.off) return null;
    final due = ref.watch(feedPredictionProvider).nextDue;
    if (due == null) return null;

    final at = TimeOfDay.fromDateTime(due).format(context);
    final overdue = !due.isAfter(now);
    return _NextFeedChip(
      overdue: overdue,
      // "Next feed 2h overdue" reads badly, so the wording flips once it has
      // slipped past.
      text: overdue
          ? 'Feed ${countdownLabel(due, now: now)} · due $at'
          : 'Next feed ${countdownLabel(due, now: now)} · $at',
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
      // Countdown leads because it's what you scan for, but on its own "in 3
      // days" doesn't tell you which day to keep free — so the concrete date
      // sits right under it.
      value: AppointmentFormat.countdown(next.at, now: now),
      detail:
          '${TimelineFormat.weekdayDate(next.at)} · '
          '${TimeOfDay.fromDateTime(next.at).format(context)}',
      footer: Text(
        details.isEmpty ? title : '$title · $details',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      accent: imminent ? theme.colorScheme.tertiary : null,
    );
  }

  static String _join(String label, String details) =>
      details.isEmpty ? label : '$label · $details';
}

/// One side of the last-fed / last-diaper pair. Compact by necessity: at half
/// a card's width there is no room for the avatar the full-width rows use.
class _HalfStat extends StatelessWidget {
  const _HalfStat({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailText = detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detailText != null)
          Text(
            detailText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            // Two lines, because half-width can't hold "9:30 AM · Bottle ·
            // 120 ml (4.1 fl oz)" on one.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// The next-feed countdown, as a tinted pill.
///
/// It used to be a small grey line under the last feed, which buried the one
/// piece of information on the row you can still act on. A filled chip at
/// [TextTheme.titleSmall] reads as its own thing, and turns to the error
/// palette once the feed is overdue.
class _NextFeedChip extends StatelessWidget {
  const _NextFeedChip({required this.text, required this.overdue});

  final String text;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = overdue
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = overdue
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            overdue ? Icons.notifications_active : Icons.schedule,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// One row: icon, label, headline value, a supporting detail, and an optional
/// footer widget.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.footer,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  /// An extra line below the detail, given as a widget so it can carry its
  /// own emphasis — the next-feed chip needs to outweigh the detail text.
  final Widget? footer;

  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Captured so the null check below reads as a plain condition rather than
    // needing a bang operator on every use.
    final detailText = detail;

    return Padding(
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
                // Label left, elapsed time hard right — matching the activity
                // list below, where every row's "x ago" sits on the right
                // edge. Pairing them on one line also buys back a line of
                // height on what had become a four-line row.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Natural width, so the value never truncates — the label
                    // ellipsizes instead if the row gets tight.
                    Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
                if (detailText != null)
                  Text(
                    detailText,
                    // bodyMedium rather than bodySmall: this is the only
                    // place the actual feed amount is shown on Home.
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ?footer,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
