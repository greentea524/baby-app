import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/repositories/repository_providers.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_quick_log.dart';
import '../home/home_status_card.dart';
import '../reminders/feed_prediction.dart';
import 'bottle_gauge.dart';
import 'bottle_sheet.dart';
import 'fridge_button.dart';
import 'fridge_order.dart';

/// What bottles are in the fridge, laid out the way the fridge is.
///
/// Oldest on the left, newest on the right: the order milk should be used
/// in, so the bottle to reach for next is always the first one.
///
/// Its own screen rather than a card on Home. Home answers "when did that last
/// happen"; this answers "what have I got", which is a different question and
/// a longer answer.
class FridgeScreen extends ConsumerWidget {
  const FridgeScreen({super.key, this.now});

  /// A fixed clock, for tests. Every card reads "3 hr ago", which is measured
  /// from somewhere.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(fridgeShelfProvider);
    // Subscribed for the whole visit so the session is resolved before
    // anybody taps Add — see [_add].
    final lastPump = ref.watch(lastPumpingProvider);
    final feeds = ref.watch(recentFeedingsProvider).value ?? const [];

    // Watched above, not read inside the sheet: this keeps the last-pump
    // stream live for as long as the screen is open, so the prefill is
    // already in hand by the time the sheet asks for it. The last session
    // only while its milk is unaccounted for. Once it is in a bottle, or has
    // been fed, offering its amount again would put the same milk in the
    // fridge twice.
    void add() => showBottleSheet(
      context,
      prefillFrom: unbottledPump(lastPump, shelf: shelf, feeds: feeds),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('In the fridge')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: const Text('Add bottle'),
      ),
      body: SafeArea(
        child: shelf.isEmpty
            ? const _EmptyFridge()
            : _Shelf(shelf: shelf, now: now ?? DateTime.now()),
      ),
    );
  }
}

class _Shelf extends ConsumerWidget {
  const _Shelf({required this.shelf, required this.now});

  /// Oldest first.
  final List<FridgeBottle> shelf;
  final DateTime now;

  /// Wide enough for an amount and a date at a readable size, narrow enough
  /// that a second bottle is visibly there to scroll to.
  static const _cardWidth = 150.0;

  /// The least height the shelf is ever given: room for a card with its
  /// bottle beside its numbers and its Finished button, at any text size.
  ///
  /// Below it, the page scrolls rather than squeezing the shelf. Measured, not
  /// guessed: a phone on its side at the largest text size has 334pt under
  /// the app bar, the summary took 190 of it, and the cards were left 40pt —
  /// too little for even their label. On a small phone upright at that size
  /// the summary took nearly everything, and the cards drew at no height at
  /// all, invisibly and without an error.
  static const _minShelf = 330.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final byKind = totalByKind(shelf);
    int aged(BottleAge age) =>
        shelf.where((b) => BottleAge.of(b.filledAt, now) == age).length;
    // Named at the top as well, because the shelf scrolls sideways: a red
    // bottle under Other may be off the edge of the screen.
    final pastDrinkBy = shelf
        .where((b) => isPastDrinkBy(b.filledAt, now))
        .length;
    final ageLine = [
      if (pastDrinkBy > 0)
        '$pastDrinkBy ${pastDrinkBy == 1 ? 'is' : 'are'} past drink-by',
      if (aged(BottleAge.old) - pastDrinkBy case final n when n > 0)
        '$n ${n == 1 ? 'is' : 'are'} 3+ days old',
      if (aged(BottleAge.aging) case final n when n > 0)
        '$n ${n == 1 ? 'is' : 'are'} 2+ days old',
    ].join(' · ');

    final summary = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${shelf.length} ${shelf.length == 1 ? 'bottle' : 'bottles'}'
            ' · ${formatVolume(totalMl(shelf), units)}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          // Broken out only when there is something to break out: on a
          // shelf of one kind this would repeat the total above it.
          if (byKind.length > 1)
            Text(
              byKind.entries
                  .map((e) => '${e.key.label} ${formatVolume(e.value, units)}')
                  .join('  ·  '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (ageLine.isNotEmpty)
            Text(
              ageLine,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          const _SyncLine(),
          const SizedBox(height: 2),
          Text(
            'Oldest on the left: use those first.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    Widget card(FridgeBottle b) => _BottleCard(
      bottle: b,
      units: units,
      now: now,
      onFinished: () => _finish(context, ref, b, now),
    );

    // The shelf takes a height rather than wrapping its cards: a fixed-height
    // band is what a shelf looks like, and the cards lay themselves out to
    // it.
    Widget list(ScrollController controller) => ListView.separated(
      controller: controller,
      scrollDirection: Axis.horizontal,
      // Clear of the Add button at the bottom. Without the gap it sat
      // over the last card, on top of the very lines that say when that
      // bottle was pumped.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: shelf.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      // As tall as the card needs, from the top of the shelf, rather than
      // stretched to the height of it.
      itemBuilder: (context, i) => SizedBox(
        key: ValueKey(shelf[i].id),
        width: _cardWidth,
        child: Align(alignment: Alignment.topCenter, child: card(shelf[i])),
      ),
    );

    // The shelf takes exactly what the summary leaves, and never less than
    // [_minShelf] — when that is more than is left, the page scrolls.
    //
    // Measured after the summary is laid out rather than guessed from the
    // screen: how tall the summary is depends on the text size and on how its
    // lines wrap at this width, and a guess from the screen height alone gave
    // one phone at the largest text a shelf of nothing.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: summary),
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final left =
                constraints.viewportMainAxisExtent -
                constraints.precedingScrollExtent;
            return SliverToBoxAdapter(
              child: SizedBox(
                height: left > _minShelf ? left : _minShelf,
                child: _ShelfScroller(step: _cardWidth + 12, builder: list),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The shelf's sideways scroll, made usable with a mouse.
///
/// A phone scrolls it with a swipe. A browser on a computer could not:
/// Flutter does not drag-scroll with a mouse by default, and a mouse wheel
/// scrolls up and down, so bottles past the edge of the window could not be
/// reached at all. Here the mouse drags like a finger, a scrollbar shows
/// there is more and can be pulled, and arrows at either end step along a
/// bottle at a time.
///
/// The arrows and the always-shown scrollbar are for computers only, which
/// is what the platform says even in a browser; a phone's browser keeps the
/// plain swipe that already works there.
class _ShelfScroller extends StatefulWidget {
  const _ShelfScroller({required this.step, required this.builder});

  /// How far one arrow press moves: a card and its gap.
  final double step;

  final Widget Function(ScrollController controller) builder;

  @override
  State<_ShelfScroller> createState() => _ShelfScrollerState();
}

class _ShelfScrollerState extends State<_ShelfScroller> {
  final _controller = ScrollController();

  /// The shelf's extent and position as last laid out or scrolled; what the
  /// arrows are shown by. From notifications rather than the controller,
  /// which says nothing when the shelf is first laid out, or when a bottle
  /// added or taken away changes how far there is to go.
  final _metrics = ValueNotifier<ScrollMetrics?>(null);

  /// The shelf's bottom padding, which the cards stop short of to stay
  /// clear of the Add button. The arrows centre on the cards, not on that.
  static const double _cardsBottom = 88;

  @override
  void dispose() {
    _controller.dispose();
    _metrics.dispose();
    super.dispose();
  }

  bool _noted(Notification n) {
    final metrics = switch (n) {
      ScrollMetricsNotification(:final metrics) => metrics,
      ScrollNotification(:final metrics) => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.horizontal) {
      _metrics.value = metrics.copyWith();
    }
    return false;
  }

  void _step(int direction) {
    final position = _controller.position;
    // Two cards at a time on a wide window, one on a narrow one, so a press
    // never skips past a bottle that was not yet seen.
    final cards = (position.viewportDimension / widget.step / 2).floor();
    final by = widget.step * (cards < 1 ? 1 : cards);
    final target = (position.pixels + direction * by).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      _ => true,
    };
    final mq = MediaQuery.of(context);

    Widget shelf = ScrollConfiguration(
      // Every kind of pointer drags, the mouse included.
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: widget.builder(_controller),
    );
    if (!desktop) return shelf;

    shelf = MediaQuery(
      // The scrollbar insets itself by the padding it is given: lifted
      // clear of the Add button, and in from the edges with the cards.
      data: mq.copyWith(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, _cardsBottom - 14),
      ),
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        interactive: true,
        child: MediaQuery(data: mq, child: shelf),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<Notification>(
            onNotification: _noted,
            child: shelf,
          ),
        ),
        Positioned.fill(
          bottom: _cardsBottom,
          child: ValueListenableBuilder(
            valueListenable: _metrics,
            builder: (context, p, _) {
              return Row(
                children: [
                  if (p != null && p.extentBefore > 0)
                    _ShelfArrow(
                      icon: Icons.chevron_left,
                      tooltip: 'Earlier bottles',
                      onPressed: () => _step(-1),
                    ),
                  const Spacer(),
                  if (p != null && p.extentAfter > 0)
                    _ShelfArrow(
                      icon: Icons.chevron_right,
                      tooltip: 'More bottles',
                      onPressed: () => _step(1),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One of the shelf's arrows: raised off the cards it sits over, so it does
/// not read as part of one.
class _ShelfArrow extends StatelessWidget {
  const _ShelfArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 28,
        style: IconButton.styleFrom(
          elevation: 3,
          shadowColor: scheme.shadow,
          minimumSize: const Size(48, 48),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

/// Says when this device's fridge is not in step with everyone else's —
/// offline, or holding a change it has not sent yet — and nothing when it is.
///
/// Two phones showing different fridges is either one of these, or one of
/// them running an older version of the app; this line rules the first out
/// at a glance, and Settings shows the version for the second.
class _SyncLine extends ConsumerWidget {
  const _SyncLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(fridgeSyncProvider).value;
    if (sync == null) return const SizedBox.shrink();
    final (icon, text) = switch (sync) {
      (pending: true, fromCache: _) => (
        Icons.cloud_upload_outlined,
        'Not sent yet — other devices will see this once it is.',
      ),
      (pending: false, fromCache: true) => (
        Icons.cloud_off_outlined,
        'Offline — showing the fridge as it was last synced.',
      ),
      _ => (null, null),
    };
    if (icon == null || text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Logs a finished bottle as a feed, and takes it off the shelf.
///
/// Opens the bottle form with this bottle in it rather than removing it on
/// the spot: a bottle out of the fridge is a feed, and removing it without
/// logging one meant logging it again by hand from Home. The bottle leaves
/// the shelf when the feed is saved, and stays if the sheet is closed — so
/// a mistaken press costs nothing. A bottle poured away rather than fed
/// is removed from its own sheet, under the card.
///
/// The removal is not through `saveAndClose`, which is the feed sheet's to
/// call. Otherwise the same shape: started at once, the shelf updates from the
/// local cache, and only a failure says anything, on this screen, which is
/// still underneath when the sheet has gone.
void _finish(
  BuildContext context,
  WidgetRef ref,
  FridgeBottle bottle,
  DateTime now,
) {
  final repo = ref.read(fridgeRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final when = FeedingFormat.clockStamp(context, bottle.filledAt, now: now);
  final notes = bottle.notes?.trim() ?? '';

  showFeedingQuickLog(
    context,
    draft: BottleDraft(
      amountMl: bottle.amountMl,
      source:
          'From the fridge, ${bottle.kind.filledLabel.toLowerCase()} $when. '
          'Saving takes it off the shelf.',
      notes: notes.isEmpty ? null : notes,
      milk: bottle.kind,
      onSaved: () {
        if (repo == null) return;
        unawaited(
          Future.sync(() => repo.delete(bottle.id)).catchError((Object e) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'The feed is logged, but the bottle could not be taken '
                  'off the shelf: $e',
                ),
              ),
            );
          }),
        );
      },
    ),
  );
}

/// One bottle: how much, when it was pumped, and how old that makes it.
class _BottleCard extends StatelessWidget {
  const _BottleCard({
    required this.bottle,
    required this.units,
    required this.now,
    required this.onFinished,
  });

  final FridgeBottle bottle;
  final UnitSystem units;
  final DateTime now;

  /// The bottle has been fed: log it, and take it off the shelf.
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final header = Row(
      children: [
        // Named, not left to the colour of the milk. Which kind a bottle is
        // changes how long it keeps, so it is not something to infer from a
        // tint across a kitchen.
        Expanded(
          child: Text(
            bottle.kind.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Keeps the line as tall as it was with the drag handle that used
        // to sit here, which the rest of the card is measured against.
        const SizedBox(height: 20),
      ],
    );

    final gauge = BottleGauge(amountMl: bottle.amountMl, kind: bottle.kind);

    // The quick way out of the fridge, one tap from the shelf. Taking a
    // bottle out is what this screen is used for most, and it used to be two
    // taps — open the bottle, then Remove — for the commonest thing anyone
    // does here. Full width and at the foot of the card, where a thumb
    // reaching for this bottle lands, and a button of its own inside the
    // card, so pressing it never also opens the bottle.
    //
    // The label is scaled to fit rather than wrapped. A card is a third of a
    // phone wide, and at the larger text sizes "Finished" and its tick broke
    // over three lines into a button 160pt tall that pushed the card over
    // the edge of the shelf.
    final finished = SizedBox(
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: onFinished,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 18),
              SizedBox(width: 6),
              Text('Finished', maxLines: 1),
            ],
          ),
        ),
      ),
    );

    // Yellow from two days, red from three: the same amber and red Home
    // uses for something coming due, so the two read as one warning. The
    // whole card is tinted, since it is the bottle that is getting old; the
    // age line inside says it in words too.
    final age = BottleAge.of(bottle.filledAt, now);
    final shelfLife = _ShelfLifeBar(bottle: bottle, now: now);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: switch (_dueStateOf(age)) {
        final state? => dueTint(context, state, scheme.surfaceContainerLow),
        null => null,
      },
      child: InkWell(
        onTap: () => showBottleSheet(context, existing: bottle),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          // Two shapes, chosen by the height the shelf gives. Tall — a phone
          // or tablet upright — and the bottle stands in the card above its
          // numbers, which is what a shelf of bottles looks like. Short — a
          // phone on its side, or a large text size eating the height — and
          // it sits beside them instead, because a bottle squeezed to a sliver
          // above four lines of text is neither.
          //
          // In the tall shape the bottle gives way to the text, not the other
          // way round: it is drawn as large as the height left over allows,
          // up to the card's full width. It used to insist on full width —
          // about 250pt — and a phone upright rarely had that to spare, so
          // most phones got the short shape, whose numbers are squeezed into
          // the narrow column beside the bottle and shrunk to fit. The times
          // are what this screen is read for, so they keep the full width.
          //
          // The short shape is left for when even a small bottle will not
          // fit above the text: a phone on its side, or the largest text.
          child: LayoutBuilder(
            builder: (context, c) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              // Everything but the bottle is text, and grows with the text
              // size: the header, the amount, the two time lines, the note,
              // the button and the gaps between them.
              // The drink-by label and date are the last 48 of them. The
              // shelf-life bar and its gap are the 16 that do not grow.
              final textHeight = 66 + (152 + 76) * scale;
              final fullBottle = c.maxWidth / BottleGauge.aspectRatio;
              final bottleRoom = c.maxHeight - textHeight;
              final tall = bottleRoom >= _minBottleHeight;

              if (tall) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: 8),
                    Center(
                      child: SizedBox(
                        height: bottleRoom < fullBottle
                            ? bottleRoom
                            : fullBottle,
                        child: gauge,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Facts(bottle: bottle, units: units, now: now),
                    const SizedBox(height: 8),
                    shelfLife,
                    const SizedBox(height: 10),
                    finished,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 6),
                  Expanded(
                    child: Row(
                      children: [
                        // Capped, because the bottle keeps its shape: given a
                        // tall card and no limit across, it grew as wide as
                        // its height asked and ran off the side of the card.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: c.maxWidth * 0.4,
                          ),
                          child: gauge,
                        ),
                        const SizedBox(width: 10),
                        // Scaled down rather than overflowing: the height here
                        // is whatever is left, and at the largest text sizes
                        // that is less than four lines want.
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _Facts(
                              bottle: bottle,
                              units: units,
                              now: now,
                              showNotes: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  shelfLife,
                  const SizedBox(height: 6),
                  finished,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The warning colours for a bottle of [age]: none while fresh.
DueState? _dueStateOf(BottleAge age) => switch (age) {
  BottleAge.fresh => null,
  BottleAge.aging => DueState.soon,
  BottleAge.old => DueState.overdue,
};

/// "9 hr ago", or, once the bottle is two days old, the same with an icon
/// and in the warning's own ink — so its age is said in words and shape as
/// well as in the card's colour.
class _AgeLine extends StatelessWidget {
  const _AgeLine({required this.bottle, required this.now});

  final FridgeBottle bottle;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ago = hoursAgo(bottle.filledAt, now);
    final state = _dueStateOf(BottleAge.of(bottle.filledAt, now));
    if (state == null) {
      return Text(
        ago,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
      );
    }
    final colours = dueColors(context, state);
    final old = state == DueState.overdue;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          old ? Icons.warning_amber_rounded : Icons.schedule,
          size: 16,
          color: colours.foreground,
        ),
        const SizedBox(width: 4),
        Text(
          ago,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colours.foreground,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
        ),
      ],
    );
  }
}

/// The smallest the bottle is drawn above the text before the card turns on
/// its side instead. Below this a bottle's level is hard to judge by eye.
const double _minBottleHeight = 110;

/// "Drink by" over "Oct 5, 5:06 AM" — [drinkWithinDays] after the bottle
/// was filled — or, once that has passed, "Past drink-by" in the error
/// colour with a warning icon, so it is said in words and shape and not by
/// colour alone.
///
/// Two lines, so the date can be the same size as the time it was pumped:
/// on one line "Drink by tomorrow, 4:00 PM" was the longest line on the
/// card and was shrunk smallest to fit, when it is the one most worth
/// reading at a glance.
class _DrinkBy extends StatelessWidget {
  const _DrinkBy({required this.bottle, required this.now});

  final FridgeBottle bottle;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deadline = drinkBy(bottle.filledAt);
    final clock = TimeOfDay.fromDateTime(deadline).format(context);
    final when = drinkByText(deadline, now, clock);
    final past = isPastDrinkBy(bottle.filledAt, now);
    final colour = past
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FitLine(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  past ? Icons.error_outline : Icons.event_outlined,
                  size: 16,
                  color: colour,
                ),
                const SizedBox(width: 4),
                Text(
                  past ? 'Past drink-by' : 'Drink by',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colour,
                    fontWeight: past ? FontWeight.w700 : null,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          _FitLine(
            child: Text(
              when,
              style: theme.textTheme.titleMedium?.copyWith(
                color: past ? colour : null,
                fontWeight: past ? FontWeight.w700 : null,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The time a bottle has left until its drink-by, as a bar that empties
/// from full when it was filled to nothing at the deadline — the same kind
/// of depleting track as Home's next-feed chip, so it reads the same way.
///
/// Banded by the warning each stretch of it falls in: the far end is red,
/// the stretch before it amber, the rest the app's own colour. So the bar
/// shows what is coming as well as what is left — as it empties, the
/// ordinary stretch goes first, and how much is left before amber is the
/// card's time until it turns yellow. Saturated rather than the card tints,
/// which a bar this thin would lose against a card already that colour.
class _ShelfLifeBar extends StatelessWidget {
  const _ShelfLifeBar({required this.bottle, required this.now});

  final FridgeBottle bottle;
  final DateTime now;

  static const double _height = 8;

  static const _amberLight = Color(0xFFD99A00);
  static const _amberDark = Color(0xFFFFC94D);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final filled = bottle.filledAt;
    final left = drinkByRemaining(filled, now);
    // Where the bar turns: below these, what is left is amber, then red.
    final amberFrom = drinkByRemainingAt(BottleAge.agingAfter, filled);
    final redFrom = drinkByRemainingAt(BottleAge.oldAfter, filled);
    final bands = [
      (from: 0.0, to: redFrom, colour: scheme.error),
      (from: redFrom, to: amberFrom, colour: dark ? _amberDark : _amberLight),
      (from: amberFrom, to: 1.0, colour: scheme.primary),
    ];
    final hoursLeft = drinkBy(filled).difference(now).inHours;

    return Semantics(
      label: left <= 0
          ? 'Past its drink-by time'
          : '$hoursLeft hr left before its drink-by time',
      child: ExcludeSemantics(
        child: SizedBox(
          height: _height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_height / 2),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: scheme.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                    for (final band in bands)
                      if (left > band.from)
                        Positioned(
                          left: w * band.from,
                          top: 0,
                          bottom: 0,
                          width:
                              w *
                              ((left < band.to ? left : band.to) - band.from),
                          child: ColoredBox(color: band.colour),
                        ),
                    // Cut between the bands, so where one ends is plain
                    // whether the bar has reached it yet or not.
                    for (final at in [redFrom, amberFrom])
                      Positioned(
                        left: w * at - 1,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: ColoredBox(color: scheme.surface),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One line of the card, shrunk to fit its width rather than cut short.
class _FitLine extends StatelessWidget {
  const _FitLine({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: child,
  );
}

/// What the bottle says in words: how much, when, how long ago.
class _Facts extends StatelessWidget {
  const _Facts({
    required this.bottle,
    required this.units,
    required this.now,
    this.showNotes = true,
  });

  final FridgeBottle bottle;
  final UnitSystem units;
  final DateTime now;

  /// Off where there is no room. A note is a sentence, and a sentence is the
  /// first thing to give on a card this size.
  final bool showNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notes = bottle.notes?.trim() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The amount is the headline: the drawing is for the glance, the
        // number is for the record. The unit rides on the same line and the
        // same baseline — on a line of its own it read as a second, unrelated
        // fact. Scaled down rather than wrapped, since in US units the line
        // carries the ounces too.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatMl(bottle.amountMl),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                units.isMetric
                    ? 'ml'
                    : 'ml · ${formatFlOz(bottle.amountMl)} fl oz',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // The when and the how-long-ago are what this screen is read for at
        // an open fridge, at arm's length — so a size up from body text, and
        // scaled down to fit rather than cut off with an ellipsis: "Sep 30,
        // 5:06 AM" with its last characters missing is a different time.
        _FitLine(
          child: Text(
            FeedingFormat.clockStamp(context, bottle.filledAt, now: now),
            style: theme.textTheme.titleMedium,
            maxLines: 1,
          ),
        ),
        _FitLine(
          child: _AgeLine(bottle: bottle, now: now),
        ),
        const SizedBox(height: 4),
        _DrinkBy(bottle: bottle, now: now),
        // The line is kept whether or not there is a note to put on it, so
        // every card is the same height and every bottle stands at the same
        // level. Without it, a card with a note grew a line and pushed its
        // bottle up above its neighbours' — on a row whose point is to compare
        // levels at a glance.
        if (showNotes) ...[
          const SizedBox(height: 4),
          Visibility(
            visible: notes.isNotEmpty,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Text(
              notes.isEmpty ? ' ' : notes,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// Nothing in the fridge — which is a normal state, not a problem.
class _EmptyFridge extends StatelessWidget {
  const _EmptyFridge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable for the same reason the shelf is: at the largest text size
    // on a phone on its side, these three lines are taller than the screen.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FridgeButton.icon,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing in the fridge',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a bottle as you put one in — pumped or made up. A '
              'pumped one opens on your last session, so it is usually one '
              'tap.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
