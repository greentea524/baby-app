import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../data/models/appointment.dart';
import '../../data/models/feeding_event.dart';
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
    // The same rows either way — only the grouping differs, so there is one
    // set of rows to maintain rather than two layouts.
    final rows = <Widget>[
      _feedingRow(context, ref),
      ?_solidsRow(context, ref),
      _diaperRow(context, ref),
      ?_appointmentSection(context, ref),
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

  /// Last milk feed on top, next due underneath.
  Widget _feedingRow(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastMilkFeedProvider);
    final units = ref.watch(unitSystemProvider);
    final due = ref.watch(nextFeedDueProvider);

    Widget? next;
    if (due != null) {
      final at = TimeOfDay.fromDateTime(due).format(context);
      final overdue = !due.isAfter(now);
      next = _NextFeedChip(
        overdue: overdue,
        // "Next feed 2h overdue" reads badly, so the wording flips once it
        // has slipped past.
        text: overdue
            ? 'Feed ${countdownLabel(due, now: now)} · due $at'
            : 'Next feed ${countdownLabel(due, now: now)} · $at',
      );
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
                FeedingFormat.details(last, units),
              ),
            ),
      footer: next,
    );
  }

  /// Solids, with no countdown attached.
  ///
  /// Null until solids have actually been logged — a permanently empty "Last
  /// ate" row would be clutter for every family not weaning yet. Deliberately
  /// has no next-feed chip: solids don't drive the milk clock, and there is
  /// no meaningful "next solids" to predict.
  Widget? _solidsRow(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastSolidsProvider);
    if (last == null) return null;
    final units = ref.watch(unitSystemProvider);

    return _StatusRow(
      icon: FeedingFormat.typeIcon(FeedingType.solids),
      label: 'Last ate',
      value: FeedingFormat.timeAgo(last.startTime, now: now),
      detail: _join(
        FeedingFormat.clockStamp(context, last.startTime, now: now),
        _join(
          FeedingFormat.typeLabel(last.type),
          FeedingFormat.details(last, units),
        ),
      ),
    );
  }

  Widget _diaperRow(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastDiaperProvider);
    return _StatusRow(
      icon: last == null
          ? Icons.baby_changing_station
          : DiaperFormat.typeIcon(last.type),
      label: 'Last diaper changed',
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

  /// The next few appointments, as one section.
  ///
  /// Null when nothing is scheduled — a permanent "no appointments" row would
  /// be clutter for anyone not using them.
  Widget? _appointmentSection(BuildContext context, WidgetRef ref) {
    final all = ref.watch(appointmentsProvider).value ?? const [];
    final upcoming = splitAppointments(all, now).upcoming;
    if (upcoming.isEmpty) return null;

    final wanted = ref.watch(homeAppointmentCountProvider);
    return AppointmentsSection(
      appointments: upcoming.take(wanted).toList(),
      now: now,
    );
  }

  static String _join(String label, String details) =>
      details.isEmpty ? label : '$label · $details';
}

/// The upcoming appointments, side by side under one icon.
///
/// Every appointment gets the same block — label, countdown, date, what it is
/// — so none of them reads as a different kind of thing. Splitting them across
/// columns is what keeps the section short enough to stay one card, which
/// stacking full-height rows would not.
///
/// Falls back to stacking when the columns would be too narrow to hold a date
/// without truncating it, which is the common case on a phone.
class AppointmentsSection extends StatelessWidget {
  const AppointmentsSection({
    super.key,
    required this.appointments,
    required this.now,
  });

  final List<Appointment> appointments;
  final DateTime now;

  /// Roughly what "Thu, Aug 6 · 2:00 PM" needs at bodyMedium. Below this a
  /// column ellipsizes the date itself, at which point stacking reads better
  /// than truncating.
  static const minColumnWidth = 150.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = appointments.first;
    final imminent = AppointmentFormat.daysUntil(first.at, now: now) <= 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One icon for the section, not one per appointment: it marks the
          // row as "appointments" the way the feeding and diaper rows do, and
          // repeating it per column would eat the width the split needs.
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              AppointmentFormat.kindIcon(first.kind),
              color: imminent
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fits =
                    appointments.length > 1 &&
                    constraints.maxWidth / appointments.length >=
                        minColumnWidth;
                return fits ? _split(context) : _stacked(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _split(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, appt) in appointments.indexed) ...[
            if (i > 0) ...[
              const SizedBox(width: 12),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: AppointmentBlock(appt: appt, now: now, isNext: i == 0),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stacked(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, appt) in appointments.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          AppointmentBlock(appt: appt, now: now, isNext: i == 0),
        ],
      ],
    );
  }
}

/// One appointment: when it is, which day, and what it is.
///
/// Identical for every appointment in the section — only the label and the
/// imminent accent tell the next one apart, so nothing reads as a different
/// class of item.
class AppointmentBlock extends StatelessWidget {
  const AppointmentBlock({
    super.key,
    required this.appt,
    required this.now,
    required this.isNext,
  });

  final Appointment appt;
  final DateTime now;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imminent = AppointmentFormat.daysUntil(appt.at, now: now) <= 1;
    final details = AppointmentFormat.details(appt);
    final title = AppointmentFormat.title(appt);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isNext ? 'Next appointment' : 'Then',
          style: theme.textTheme.labelMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          AppointmentFormat.countdown(appt.at, now: now),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            // Only a visit within a day earns the accent, and only when it is
            // the next one — a later appointment tinted the same way would
            // compete with what needs attention today.
            color: imminent && isNext ? theme.colorScheme.tertiary : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${TimelineFormat.weekdayDate(appt.at)} · '
          '${TimeOfDay.fromDateTime(appt.at).format(context)}',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          details.isEmpty ? title : '$title · $details',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
          maxLines: 1,
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
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  /// An extra line below the detail, given as a widget so it can carry its
  /// own emphasis — the next-feed chip needs to outweigh the detail text.
  final Widget? footer;

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
            child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
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
