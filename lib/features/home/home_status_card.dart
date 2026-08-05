import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../data/models/feeding_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../diaper/diaper_format.dart';
import '../feeding/feeding_format.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';
import 'home_prefs.dart';

/// The Home status card (KAN-179): where feeding and diapers stand.
///
/// The next appointment used to sit here too, but it is the one thing on Home
/// you cannot act on today — it now lives in the app bar corner
/// (`NextAppointmentButton`), leaving these rows to what you can.
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
      final state = feedDueState(
        due,
        now: now,
        within: ref.watch(reminderSettingsProvider).headsUp,
      );
      next = NextFeedChip(
        state: state,
        // "Next feed 2h overdue" reads badly, so the wording flips once it
        // has slipped past.
        text: state == FeedDueState.overdue
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
                FeedingFormat.eventLabel(last),
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

  static String _join(String label, String details) =>
      details.isEmpty ? label : '$label · $details';
}

/// The next-feed countdown, as a tinted pill.
///
/// It used to be a small grey line under the last feed, which buried the one
/// piece of information on the row you can still act on. A filled chip at
/// [TextTheme.titleSmall] reads as its own thing, and warms through amber to
/// the error palette as the feed comes due.
class NextFeedChip extends StatelessWidget {
  const NextFeedChip({super.key, required this.text, required this.state});

  final String text;
  final FeedDueState state;

  /// Amber is spelled out rather than taken from the scheme because no Material
  /// role means "warning": the seed decides what `tertiary` looks like, and
  /// across this app's four accents it lands anywhere from pink to green. A
  /// caution colour has to mean caution whichever accent is chosen, the same
  /// way `error` does.
  static const _soonLight = (
    background: Color(0xFFFFE7A8),
    foreground: Color(0xFF5A4200),
  );
  // Brighter than a Material dark container usually runs. `errorContainer` is
  // vivid in this scheme, and a dim amber next to it broke the escalation:
  // upcoming and soon both read as "not the red one".
  static const _soonDark = (
    background: Color(0xFF6B5200),
    foreground: Color(0xFFFFE7A8),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final soon = theme.brightness == Brightness.dark ? _soonDark : _soonLight;

    final (background, foreground, icon) = switch (state) {
      FeedDueState.overdue => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.notifications_active,
      ),
      FeedDueState.soon => (
        soon.background,
        soon.foreground,
        Icons.notifications_none,
      ),
      FeedDueState.upcoming => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.schedule,
      ),
    };

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
          Icon(icon, size: 16, color: foreground),
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
