import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/models/feeding_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../common/banded_track.dart';
import '../diaper/diaper_due.dart';
import '../diaper/diaper_format.dart';
import '../feeding/feeding_format.dart';
import '../fridge/fridge_button.dart';
import '../fridge/fridge_order.dart';
import '../pumping/pump_schedule.dart';
import '../pumping/pumping_format.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';
import '../diaper/diaper_quick_log.dart';
import '../feeding/feeding_quick_log.dart';
import '../pumping/pumping_quick_log.dart';
import '../fridge/bottle_gauge.dart';
import '../fridge/bottle_sheet.dart';
import 'home_prefs.dart';

/// The Home status card (KAN-179): where feeding, diapers and pumping stand.
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
      ?_pumpRow(context, ref),
      ?_fridgeRow(context, ref),
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
              // Indented to the text, not the icon: the icons then run down
              // the card as one column, and each rule underlines the row it
              // ends rather than cutting across the column.
              if (i > 0)
                const Divider(
                  height: 1,
                  indent: _StatusRow.textInset,
                  endIndent: 16,
                ),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  /// The last milk feed, and when the next one is due.
  Widget _feedingRow(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastMilkFeedProvider);
    final units = ref.watch(unitSystemProvider);
    final due = ref.watch(nextFeedDueProvider);

    DueState? state;
    Widget? next;
    if (due != null) {
      final at = _keep(TimeOfDay.fromDateTime(due).format(context));
      final settings = ref.watch(reminderSettingsProvider);
      state = feedDueState(due, now: now, within: settings.headsUp);
      next = DueChip(
        state: state,
        remaining: feedRemaining(
          due: due,
          interval: Duration(minutes: settings.intervalMinutes),
          now: now,
        ),
        soonFrom: dueSoonShare(
          headsUp: settings.headsUp,
          interval: Duration(minutes: settings.intervalMinutes),
        ),
        // "Next feed 2h overdue" reads badly, so the wording flips once it
        // has slipped past.
        text: state == DueState.overdue
            ? 'Feed ${countdownLabel(due, now: now)} · due $at'
            : 'Next feed ${countdownLabel(due, now: now)} · $at',
      );
    }

    return _StatusRow(
      // The chip says it in words; the dot says it beside the label, where
      // a glance down the card finds it before reading anything.
      alert: state,
      icon: last == null ? Icons.child_care : FeedingFormat.typeIcon(last.type),
      onLog: () => logFeed(context, ref),
      logLabel: ref.watch(bottleShortcutProvider) ? 'Log bottle' : 'Log feed',
      label: 'Feed',
      headline: last == null
          ? 'No feeds yet'
          : _join(
              FeedingFormat.eventLabel(last),
              _keep(FeedingFormat.measure(last, units) ?? ''),
            ),
      when: last?.startTime,
      now: now,
      detail: last == null ? null : FeedingFormat.extras(last, units),
      chips: [?next],
    );
  }

  /// Solids, with no countdown attached.
  ///
  /// Null until solids have actually been logged — a permanently empty
  /// solids row would be clutter for every family not weaning yet.
  /// Deliberately has no next-feed chip: solids don't drive the milk clock,
  /// and there is no meaningful "next solids" to predict.
  Widget? _solidsRow(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastSolidsProvider);
    if (last == null) return null;
    final units = ref.watch(unitSystemProvider);

    return _StatusRow(
      icon: FeedingFormat.typeIcon(FeedingType.solids),
      onLog: () => showFeedingQuickLog(context, type: FeedingType.solids),
      logLabel: 'Log solids',
      label: 'Solids',
      headline: _join(
        FeedingFormat.eventLabel(last),
        _keep(FeedingFormat.measure(last, units) ?? ''),
      ),
      when: last.startTime,
      now: now,
      detail: FeedingFormat.extras(last, units),
    );
  }

  Widget _diaperRow(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastDiaperProvider);
    final state = diaperDueState(last?.time, now: now);
    final notes = last?.notes?.trim() ?? '';
    return _StatusRow(
      // Its own clock, escalating like the feed row above it: amber at two
      // hours since the last change, red at three. The dot is all that says
      // so on this row, so it is said to a screen reader too.
      alert: state,
      alertLabel: switch (state) {
        DueState.overdue => 'Change overdue',
        DueState.soon => 'Change due soon',
        _ => null,
      },
      icon: last == null
          ? Icons.baby_changing_station
          : DiaperFormat.typeIcon(last.type),
      onLog: () => showDiaperQuickLog(context),
      logLabel: 'Log diaper',
      label: 'Diaper',
      headline: last == null ? 'No changes yet' : DiaperFormat.summary(last),
      when: last?.time,
      now: now,
      detail: notes,
    );
  }

  /// The last pump session, and when the next one is due.
  ///
  /// Two things have to be true before it appears. Pumping has to be
  /// switched on — a household that hid the pumping action has said pumping
  /// is not part of their day, the same reading the bottle suggestion chips
  /// take of that preference — and there has to be a session to show, so the
  /// row does not sit empty on the day the setting is first left alone.
  ///
  /// The countdown is a third condition on top of those, and only on the
  /// chip: a cadence has to have been set (see [pumpIntervalProvider], which
  /// is off until it is). Without one the row is what it was before — when
  /// the last session was, and no colour — because there is nothing to be
  /// late for. With one it escalates exactly like the feeding row, chip and
  /// dot together, since a caregiver who set a cadence did so to be told
  /// when it has slipped.
  Widget? _pumpRow(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showPumpingActionProvider)) return null;
    final last = ref.watch(lastPumpingProvider);
    final units = ref.watch(unitSystemProvider);
    final due = ref.watch(nextPumpDueProvider);

    DueState? state;
    Widget? next;
    if (due != null) {
      // The heads-up the caregiver already chose for feeds. It is an answer
      // to "how much notice do I want", which does not change subject with
      // the row, and a second dropdown asking it again would be a setting
      // earning its keep only in the settings screen.
      final headsUp = ref.watch(reminderSettingsProvider).headsUp;
      state = feedDueState(due, now: now, within: headsUp);
      final at = _keep(TimeOfDay.fromDateTime(due).format(context));
      next = DueChip(
        state: state,
        remaining: feedRemaining(
          due: due,
          interval: Duration(minutes: ref.watch(pumpIntervalProvider)),
          now: now,
        ),
        soonFrom: dueSoonShare(
          headsUp: headsUp,
          interval: Duration(minutes: ref.watch(pumpIntervalProvider)),
        ),
        // Flipped once it has slipped past, the way the feed chip is: "Next
        // pump 40m overdue" reads as a contradiction.
        text: state == DueState.overdue
            ? 'Pump ${countdownLabel(due, now: now)} · due $at'
            : 'Next pump ${countdownLabel(due, now: now)} · $at',
      );
    }

    return _StatusRow(
      alert: state,
      icon: PumpingFormat.icon,
      onLog: () => showPumpingQuickLog(context),
      logLabel: 'Log pump',
      label: 'Pump',
      headline: last == null
          ? 'No sessions yet'
          : switch ([
              if (last.side != null) FeedingFormat.sideLabel(last.side!),
              if (PumpingFormat.measure(last, units) case final m?) _keep(m),
            ]) {
              [] => 'Pumped',
              final parts => parts.join(' · '),
            },
      when: last?.time,
      now: now,
      detail: last == null ? null : PumpingFormat.extras(last),
      chips: [?next],
    );
  }

  /// What is in the fridge, and the way in to it.
  ///
  /// A row of its own rather than a button on the pump row, where it used to
  /// be: the fridge holds formula and whole milk as well as pumped milk, and
  /// a household that hid pumping still has one. Shown whenever the fridge
  /// is switched on, empty or not — "Empty" is an answer, and the button is
  /// how a first bottle gets added.
  ///
  /// Marked by its oldest bottle, the way the fridge's own cards are: amber
  /// from two days, red from three.
  Widget? _fridgeRow(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showFridgeProvider)) return null;
    final shelf = ref.watch(fridgeShelfProvider);
    final units = ref.watch(unitSystemProvider);

    int count(bool Function(FridgeBottle b) test) => shelf.where(test).length;
    final past = count((b) => isPastDrinkBy(b.filledAt, now));
    final old = count((b) => BottleAge.of(b.filledAt, now) == BottleAge.old);
    final aging = count(
      (b) => BottleAge.of(b.filledAt, now) == BottleAge.aging,
    );
    // The most pressing one, said once: the fridge screen has the rest.
    String are(int n) => n == 1 ? 'is' : 'are';
    final warning = past > 0
        ? '$past ${are(past)} past drink-by'
        : old > 0
        ? '$old ${are(old)} 3+ days old'
        : aging > 0
        ? '$aging ${are(aging)} 2+ days old'
        : '';

    return _StatusRow(
      alert: old > 0
          ? DueState.overdue
          : aging > 0
          ? DueState.soon
          : null,
      action: const FridgeButton(glyph: Icons.arrow_forward),
      icon: FridgeButton.icon,
      onLog: () => showBottleSheet(
        context,
        prefillFrom: unbottledPump(
          ref.read(lastPumpingProvider),
          shelf: shelf,
          feeds: ref.read(recentFeedingsProvider).value ?? const [],
        ),
      ),
      logLabel: 'Add a bottle to the fridge',
      label: 'Fridge',
      headline: switch (shelf.length) {
        0 => 'Empty',
        final n => _join(
          n == 1 ? '1 bottle' : '$n bottles',
          _keep(formatVolume(totalMl(shelf), units)),
        ),
      },
      picture: _bottlePicture(shelf),
      detail: warning,
      now: now,
    );
  }

  /// The bottles themselves, up to [_maxDrawn], drawn filled to their
  /// level, oldest first as on the fridge's own shelf: three small bottles
  /// say "three, and how full" at a glance. Past that a row of drawings is
  /// slower to read than the count the headline already gives, so null.
  static Widget? _bottlePicture(List<FridgeBottle> shelf) {
    if (shelf.isEmpty || shelf.length > _maxDrawn) return null;
    const height = 40.0;
    const gap = 4.0;
    const width = height * BottleGauge.aspectRatio;
    // The headline says how many and how much; this only says it again.
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, b) in shelf.indexed) ...[
            if (i > 0) const SizedBox(width: gap),
            SizedBox(
              key: ValueKey('home-bottle-${b.id}'),
              width: width,
              height: height,
              child: BottleGauge(amountMl: b.amountMl, kind: b.kind),
            ),
          ],
        ],
      ),
    );
  }

  /// The most bottles drawn on the row before only the count is given.
  static const _maxDrawn = 3;

  /// [text] with each number held to the word after it, so "120 ml" and
  /// "2:50 PM" never come apart across a line. Only those spaces: "120 ml
  /// (4.1 fl oz)" can still break between the two.
  static String _keep(String text) =>
      text.replaceAll(RegExp(r'(?<=\d) '), '\u00a0');

  static String _join(String label, String details) =>
      details.isEmpty ? label : '$label · $details';
}

/// A countdown to something being due, as a tinted pill.
///
/// It used to be a small grey line under the last feed, which buried the one
/// piece of information on the row you can still act on. A filled chip at
/// [TextTheme.titleSmall] reads as its own thing, and warms through amber to
/// the error palette as the thing it counts to comes due.
///
/// Named for the job rather than for feeds: it carries the pump countdown on
/// the row below as well, and the wording is the caller's to supply.
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
/// Shared rather than private to [DueChip] because nursery mode tints
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

class DueChip extends StatelessWidget {
  const DueChip({
    super.key,
    required this.text,
    required this.state,
    this.remaining,
    this.soonFrom,
    this.icon,
  });

  final String text;
  final DueState state;

  /// In place of the state's own icon. Its bell says a reminder is coming,
  /// which is not true of every chip.
  final IconData? icon;

  /// How much of the gap to the next feed is left, 1 to 0, drawn as a track
  /// depleting along the chip's own bottom edge. Null draws nothing.
  ///
  /// Inside the chip rather than beside it, because it is the same fact the
  /// words are already stating and belongs to them. It costs no layout on
  /// either screen, and it tells you what the words cannot without doing
  /// arithmetic against your own interval: whether "26m" is a third of the
  /// way through or nine tenths.
  final double? remaining;

  /// Where along the track the heads-up starts — see [dueSoonShare]. The
  /// stretch below it is amber, the rest the app's colour, the way the
  /// fridge's drink-by bar is banded: so how near the chip is to turning
  /// amber can be seen, not only that it has. Null keeps it one colour.
  final double? soonFrom;

  /// Thick enough to read the bands in, thin enough to stay an underline.
  static const double _trackHeight = 4;

  @override
  Widget build(BuildContext context) {
    final (:background, :foreground, icon: stateIcon) = dueColors(
      context,
      state,
    );
    final icon = this.icon ?? stateIcon;
    final inks = warningInks(context);
    final left = remaining;
    final amber = soonFrom;

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
              child: BandedTrack(
                remaining: left,
                height: _trackHeight,
                rounded: false,
                cut: background,
                bands: [
                  if (amber != null && amber > 0)
                    (from: 0.0, to: amber, colour: inks.soon),
                  (from: amber ?? 0.0, to: 1.0, colour: inks.ok),
                ],
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
                    // Two lines before an ellipsis: at a large text size the
                    // clock time is the end of the line, and the first thing
                    // a single line would lose.
                    maxLines: 2,
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

/// One row: what it is, what happened, when, and what is coming.
///
/// Read in three passes, each down one edge of the card. The small capital
/// label says which row is which; the bold line under it is what happened —
/// "Bottle · 120 ml" — and the right-hand column is when, "2h 20m ago" over
/// the clock time, lined up from row to row so the times can be compared
/// without reading anything else. Detail too long for the headline gets a
/// line of its own under it rather than an ellipsis, and whatever is coming
/// next — a countdown, a wait — runs the full width underneath.
///
/// The rows used to lead with "Last fed" and the time ago, with what was fed
/// and the clock time run together into one grey line that the notes pushed
/// out of sight. Every row was the same shape of sentence, so nothing in it
/// stood out, and the one thing that varies — what happened — was the
/// first to be cut.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.headline,
    required this.now,
    this.when,
    this.detail,
    this.chips = const [],
    this.alert,
    this.alertLabel,
    this.picture,
    this.action,
    this.onLog,
    this.logLabel,
  });

  /// Where the text starts: the padding, the icon, and the gap after it.
  /// The card's dividers start here too.
  static const double textInset = 16 + 48 + 16;

  final IconData icon;

  /// What the row is about, set small and in capitals above the headline:
  /// "Feed". A name rather than a phrase like "Last fed", so it reads as a
  /// heading and not as the start of a sentence.
  final String label;

  /// What happened: "Bottle · 120 ml", or what to say when nothing has.
  final String headline;

  /// When it happened, for the time column. Null leaves the column out.
  final DateTime? when;
  final DateTime now;

  /// Anything else worth knowing — the milk, the notes, who gave it — on a
  /// muted line of its own. Empty or null for none.
  final String? detail;

  /// What happens next, each across the row's full width under the text.
  final List<Widget> chips;

  /// Whether this row is asking for something: a dot beside its label,
  /// amber when it soon will be and red once it is.
  ///
  /// A dot rather than colouring the whole row, as it used to. A tinted band
  /// said the same thing, but it also put every word on the row onto a
  /// coloured ground, and two or three tinted rows on one card made it hard
  /// to see where one stopped. The dot sits where the eye lands first.
  final DueState? alert;

  /// What [alert] means, for a screen reader — given only where nothing
  /// else on the row says it in words. A row with a chip has the chip.
  final String? alertLabel;

  /// Drawn at the trailing edge, beside the headline: the fridge's bottles.
  final Widget? picture;

  /// A button at the row's trailing edge, for the rows that lead anywhere.
  ///
  /// A button rather than making the whole row tappable. The row used to be
  /// one big tap target with a chevron at the end, and the chevron was all
  /// there was to say so — easy to miss, and it did not say where. A button
  /// is its own evidence of being pressable, and it is the only thing that
  /// is: nothing on the row answers a tap that does not look like it would.
  final Widget? action;

  /// Logs another of what this row reports — tapping its icon. The way to
  /// log from Home: the row's icon is the button, so the reading and the way
  /// to add to it are one thing, and there is no separate row of log buttons
  /// above the card saying the same three words again.
  final VoidCallback? onLog;

  /// What [onLog] does, for its tooltip and for a screen reader: "Log feed".
  final String? logLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = when;
    final trailing = [?picture, ?action];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        // The icon sits level with the label rather than centred on a row
        // whose height now changes with its chips.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          switch (onLog) {
            final log? => _LogIcon(
              icon: icon,
              label: logLabel ?? 'Log',
              onPressed: log,
            ),
            null => CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
            ),
          },
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Eyebrow(label: label, alert: alert, alertLabel: alertLabel),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: _Reading(
                        headline: headline,
                        detail: detail,
                        ago: at == null
                            ? null
                            : FeedingFormat.shortAgo(at, now: now),
                        clock: at == null
                            ? null
                            : FeedingFormat.clockStamp(context, at, now: now),
                      ),
                    ),
                    for (final it in trailing) ...[
                      const SizedBox(width: 8),
                      it,
                    ],
                  ],
                ),
                ...chips,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row's label, small and in capitals, with its [alert] dot in front.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label, this.alert, this.alertLabel});

  final String label;
  final DueState? alert;
  final String? alertLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inks = warningInks(context);
    final dot = switch (alert) {
      DueState.overdue => inks.overdue,
      DueState.soon => inks.soon,
      _ => null,
    };

    return Row(
      children: [
        if (dot != null) ...[
          Semantics(
            label: alertLabel,
            excludeSemantics: true,
            child: Container(
              key: const ValueKey('alert-dot'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Semantics(
            label: label,
            excludeSemantics: true,
            child: Text(
              // Spelt out in capitals rather than by a text transform, so
              // the label is the same everywhere it is measured.
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

/// What happened on the left, when on the right: [headline] level with
/// [ago], [detail] level with [clock].
///
/// The time column takes what it needs and the headline the rest, wrapping
/// if it has to — neither is ever cut short. When the times would take more
/// than [_maxTimeShare] of the width, as at a large text size on a phone,
/// they move onto a line of their own under the detail instead of
/// squeezing what happened into a sliver.
class _Reading extends StatelessWidget {
  const _Reading({required this.headline, this.detail, this.ago, this.clock});

  final String headline;
  final String? detail;
  final String? ago;
  final String? clock;

  static const _maxTimeShare = 0.5;

  /// The widest elapsed time a row commonly shows: hours run to one digit
  /// between feeds, and figures are tabular, so any such time is this wide.
  static const _widestAgo = '9h 59m ago';
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
    final muted = theme.colorScheme.onSurfaceVariant;
    final strong = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    // Tabular figures, so "2h 15m" and "11:55" line up digit for digit with
    // the rows above and below.
    final agoStyle = strong?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final clockStyle = theme.textTheme.bodyMedium?.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final detailStyle = theme.textTheme.bodyMedium?.copyWith(color: muted);
    final extra = detail;
    final hasDetail = extra != null && extra.isNotEmpty;

    final head = Text(headline, style: strong);
    final more = hasDetail
        ? Text(
            extra,
            style: detailStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        : null;

    final ago = this.ago;
    final clock = this.clock;
    if (ago == null || clock == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [head, ?more],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        // Measured against the widest elapsed time a row usually shows as
        // well as its own, so every row on the card makes the same choice:
        // decided by each row's own "4h ago" or "2h 20m ago", the card
        // came out half in columns and half stacked.
        final timeWidth = [
          _widthOf(_widestAgo, agoStyle, scaler),
          _widthOf(ago, agoStyle, scaler),
          _widthOf(clock, clockStyle, scaler),
        ].reduce((a, b) => a > b ? a : b);

        if (timeWidth + _gap > constraints.maxWidth * _maxTimeShare) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              head,
              ?more,
              Text('$ago · $clock', style: clockStyle),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [head, ?more],
              ),
            ),
            const SizedBox(width: _gap),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(ago, style: agoStyle),
                Text(clock, style: clockStyle),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Opens the feed sheet the way this household has asked for it: straight
/// to a bottle when that shortcut is on, otherwise asking what kind.
///
/// Shared by the feeding row's icon and the app's "Log feed" launch
/// shortcut, which are the same intent arriving two ways and would be a bug
/// apart.
void logFeed(BuildContext context, WidgetRef ref) {
  showFeedingQuickLog(
    context,
    type: ref.read(bottleShortcutProvider) ? FeedingType.bottle : null,
  );
}

/// A row's icon as its log button: the same picture, filled and pressable,
/// with a small plus on it so it reads as "add one" and not as decoration.
///
/// The full 48pt touch target, a little bigger than the plain icon it
/// replaces, so a thumb finds it without aiming.
class _LogIcon extends StatelessWidget {
  const _LogIcon({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IconButton.filledTonal(
              tooltip: label,
              onPressed: onPressed,
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
              ),
              icon: Icon(icon),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: IgnorePointer(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(Icons.add, size: 14, color: scheme.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
