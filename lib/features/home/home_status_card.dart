import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../data/models/feeding_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../diaper/diaper_due.dart';
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
                // The feeding row paints edge to edge when it is tinted.
                clipBehavior: Clip.antiAlias,
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
      // The feeding row paints edge to edge when it is tinted.
      clipBehavior: Clip.antiAlias,
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
      final settings = ref.watch(reminderSettingsProvider);
      final state = feedDueState(due, now: now, within: settings.headsUp);
      next = NextFeedChip(
        state: state,
        remaining: feedRemaining(
          due: due,
          interval: Duration(minutes: settings.intervalMinutes),
          now: now,
        ),
        // "Next feed 2h overdue" reads badly, so the wording flips once it
        // has slipped past.
        text: state == DueState.overdue
            ? 'Feed ${countdownLabel(due, now: now)} · due $at'
            : 'Next feed ${countdownLabel(due, now: now)} · $at',
      );
    }

    return _StatusRow(
      // The same escalation the chip carries, behind the whole row. On a
      // card of three rows the colour says which one is asking for
      // something before any of them have been read.
      tint: due == null
          ? null
          : dueTint(
              context,
              feedDueState(
                due,
                now: now,
                within: ref.watch(reminderSettingsProvider).headsUp,
              ),
              Theme.of(context).colorScheme.surfaceContainerLow,
            ),
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
      // Its own clock, escalating like the feed row above it: amber at two
      // hours since the last change, red at three.
      tint: switch (diaperDueState(last?.time, now: now)) {
        null => null,
        final state => dueTint(
          context,
          state,
          Theme.of(context).colorScheme.surfaceContainerLow,
        ),
      },
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
/// Amber is spelled out rather than taken from the scheme because no Material
/// role means "warning": the seed decides what `tertiary` looks like, and
/// across this app's four accents it lands anywhere from pink to green. A
/// caution colour has to mean caution whichever accent is chosen, the same
/// way `error` does.
const _soonLight = (
  background: Color(0xFFFFE7A8),
  foreground: Color(0xFF5A4200),
);

// Brighter than a Material dark container usually runs. `errorContainer` is
// vivid in this scheme, and a dim amber next to it broke the escalation:
// upcoming and soon both read as "not the red one".
const _soonDark = (
  background: Color(0xFF6B5200),
  foreground: Color(0xFFFFE7A8),
);

/// Overdue in a light theme, hand-picked for the same reason the amber is.
///
/// `errorContainer` reads fine as a solid chip, but this scheme places it a
/// hair from the surface — measured at (243, 227, 230) against a (235, 229,
/// 241) card — so as a tint it all but disappears, and red came out quieter
/// than amber. A warning's last step cannot be its faintest.
///
/// Dark keeps `errorContainer`: the note on [_soonDark] above already
/// records that it is vivid there, which is the whole reason that amber had
/// to be brightened to keep up with it.
const _overdueLight = (
  background: Color(0xFFFFCFCB),
  foreground: Color(0xFF5F1412),
);

/// How a feed-due state is coloured, for anything that wants to show it.
///
/// Shared rather than private to [NextFeedChip] because nursery mode tints
/// the whole "Last fed" card with the same escalation, and two copies of the
/// amber would drift apart the first time one of them was adjusted.
({Color background, Color foreground, IconData icon}) dueColors(
  BuildContext context,
  DueState state,
) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final soon = theme.brightness == Brightness.dark ? _soonDark : _soonLight;

  return switch (state) {
    DueState.overdue => (
      background: theme.brightness == Brightness.dark
          ? scheme.errorContainer
          : _overdueLight.background,
      foreground: theme.brightness == Brightness.dark
          ? scheme.onErrorContainer
          : _overdueLight.foreground,
      icon: Icons.notifications_active,
    ),
    DueState.soon => (
      background: soon.background,
      foreground: soon.foreground,
      icon: Icons.notifications_none,
    ),
    DueState.upcoming => (
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
      icon: Icons.schedule,
    ),
  };
}

/// [dueColors]'s background, softened onto [on].
///
/// Softened rather than used neat, for two reasons. The next-feed chip sits
/// on top of it and would vanish into a surface of its own exact colour; and
/// the surrounding text is `onSurface`, which is only guaranteed to read
/// against something surface-shaped.
///
/// The strength climbs with the state, and has to. A flat blend does not
/// preserve the escalation: `errorContainer` in this scheme sits close to
/// the surface, while the amber is hand-picked and saturated, so at equal
/// strength red came out *paler* than amber — the last step of a warning
/// reading as the quietest. Measured on the nursery cards, where the two sit
/// side by side and the inversion is plain.
double _tintStrength(DueState state) => switch (state) {
  DueState.upcoming => 0.35,
  DueState.soon => 0.55,
  DueState.overdue => 0.85,
};

Color dueTint(BuildContext context, DueState state, Color on) =>
    Color.alphaBlend(
      dueColors(
        context,
        state,
      ).background.withValues(alpha: _tintStrength(state)),
      on,
    );

class NextFeedChip extends StatelessWidget {
  const NextFeedChip({
    super.key,
    required this.text,
    required this.state,
    this.remaining,
  });

  final String text;
  final DueState state;

  /// How much of the gap to the next feed is left, 1 to 0, drawn as a track
  /// depleting along the chip's own bottom edge. Null draws nothing.
  ///
  /// Inside the chip rather than beside it, because it is the same fact the
  /// words are already stating and belongs to them. It costs no layout on
  /// either screen, and it tells you what the words cannot without doing
  /// arithmetic against your own interval: whether "26m" is a third of the
  /// way through or nine tenths.
  final double? remaining;

  /// Thin enough to read as an underline rather than a second element.
  static const double _trackHeight = 3;

  @override
  Widget build(BuildContext context) {
    final (:background, :foreground, :icon) = dueColors(context, state);
    final left = remaining;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      // The track runs to the chip's edge, so the corners have to cut it.
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (left != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _trackHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: left,
                  // heightFactor too: without it the box is loose vertically
                  // and a childless ColoredBox collapses to nothing, which
                  // is a track that paints no pixels.
                  heightFactor: 1,
                  child: ColoredBox(color: foreground),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              10,
              6,
              10,
              left == null ? 6 : 6 + _trackHeight,
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
    this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  /// An extra line below the detail, given as a widget so it can carry its
  /// own emphasis — the next-feed chip needs to outweigh the detail text.
  ///
  /// Aligned right, with the elapsed time above it. The two are the row's
  /// answers to the same question — when they last ate, when they next need
  /// to — and reading down the right edge is how you get both.
  final Widget? footer;

  /// Colours the row with a state it carries — for feeding, how close the
  /// next feed is. See [dueTint].
  ///
  /// Painted edge to edge rather than inset, so the row's own padding still
  /// lines its icon and text up with the untinted rows above and below. The
  /// cards clip, which is what keeps the band inside their rounded corners.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Captured so the null check below reads as a plain condition rather than
    // needing a bang operator on every use.
    final detailText = detail;

    return ColoredBox(
      color: tint ?? Colors.transparent,
      child: Padding(
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
                  _LabelAndValue(label: label, value: value),
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
                  if (footer case final it?)
                    Align(alignment: Alignment.centerRight, child: it),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row's label and its elapsed time: paired on one line when they fit,
/// stacked when they do not, and right-aligned either way.
///
/// The elapsed time sits hard right to match the activity list below, where
/// every row's "x ago" is on the right edge. Pairing the two on one line also
/// buys back a line of height on what had become a four-line row.
///
/// This was a `Wrap` with `WrapAlignment.spaceBetween`, which never did
/// anything: a `Wrap` inside a `Column` shrink-wraps to its children, so there
/// is no free space for `spaceBetween` to distribute. The time simply trailed
/// the label. Rows then disagreed with each other — on a 390pt phone "Last
/// fed" left its time 25pt short of the edge while the longer "Last diaper
/// changed" pushed its own onto a second line and against the *left* margin.
///
/// A plain `Row` is not the answer either: at a large text size the two no
/// longer fit across a phone and it overflowed visibly from 150% up. Nor can
/// a `Wrap` fix the stacked case, since it puts a lone child at the start of
/// its run. So the fit is measured and the two layouts chosen between —
/// neither string is ever truncated, because the whole row is the answer to
/// "when did they last eat".
class _LabelAndValue extends StatelessWidget {
  const _LabelAndValue({required this.label, required this.value});

  final String label;
  final String value;

  /// The least space allowed between them before they stop sharing a line.
  static const _gap = 12.0;

  static double _widthOf(String text, TextStyle? style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium;
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final scaler = MediaQuery.textScalerOf(context);

    final labelText = Text(label, style: labelStyle);
    // Right-aligned in both branches: in the Row it is the last child, and in
    // the stretched Column the alignment is what puts it against the edge.
    final valueText = Text(
      value,
      style: valueStyle,
      textAlign: TextAlign.right,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            constraints.maxWidth.isFinite &&
            _widthOf(label, labelStyle, scaler) +
                    _gap +
                    _widthOf(value, valueStyle, scaler) <=
                constraints.maxWidth;

        if (fits) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [labelText, const Spacer(), valueText],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [labelText, valueText],
        );
      },
    );
  }
}
