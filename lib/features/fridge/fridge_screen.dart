import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/repositories/repository_providers.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_quick_log.dart';
import 'bottle_gauge.dart';
import 'bottle_sheet.dart';
import 'fridge_button.dart';
import 'fridge_order.dart';

/// What bottles are in the fridge, laid out the way the shelf is.
///
/// A row rather than a list, and left to right rather than top to bottom,
/// because the point is to match something physical: you are standing at an
/// open fridge comparing what is on screen to what is in front of you. Oldest
/// on the left, which is the end you take from.
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
    final byHand = isArrangedByHand(shelf);
    // Subscribed for the whole visit so the session is resolved before
    // anybody taps Add — see the FAB below.
    final lastPump = ref.watch(lastPumpingProvider);
    final feeds = ref.watch(recentFeedingsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('In the fridge'),
        actions: [
          if (byHand)
            TextButton(
              onPressed: () =>
                  ref.read(fridgeRepositoryProvider)?.clearOrder(shelf),
              child: const Text('Sort by age'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Watched here, not read inside the sheet: this keeps the last-pump
        // stream live for as long as the screen is open, so the prefill is
        // already in hand by the time the sheet asks for it.
        // The last session only while its milk is unaccounted for. Once it
        // is in a bottle, or has been fed, offering its amount again would
        // put the same milk in the fridge twice.
        onPressed: () => showBottleSheet(
          context,
          prefillFrom: unbottledPump(lastPump, shelf: shelf, feeds: feeds),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add bottle'),
      ),
      body: SafeArea(
        child: shelf.isEmpty
            ? const _EmptyFridge()
            : _Shelf(shelf: shelf, byHand: byHand, now: now ?? DateTime.now()),
      ),
    );
  }
}

class _Shelf extends ConsumerWidget {
  const _Shelf({required this.shelf, required this.byHand, required this.now});

  final List<FridgeBottle> shelf;
  final bool byHand;
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
  static const _minShelf = 300.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final byKind = totalByKind(shelf);

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
          const SizedBox(height: 2),
          Text(
            byHand
                ? 'Arranged by hand, to match your fridge.'
                : 'Oldest on the left — the end to take from.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    // The shelf takes a height rather than wrapping its cards: a horizontal
    // reorderable list needs a bounded cross axis, and a fixed-height band is
    // also what a shelf looks like.
    final list = ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      // Clear of the Add button at the bottom. Without the gap it sat
      // over the last card, on top of the very lines that say when that
      // bottle was pumped.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      // Every card carries its own handle instead, so a tap can open
      // the bottle without a long press being ambiguous.
      buildDefaultDragHandles: false,
      itemCount: shelf.length,
      onReorderItem: (from, to) => ref
          .read(fridgeRepositoryProvider)
          ?.saveOrder(reordered(shelf, from, to)),
      proxyDecorator: (child, index, animation) =>
          Material(color: Colors.transparent, child: child),
      itemBuilder: (context, i) => Padding(
        key: ValueKey(shelf[i].id),
        padding: const EdgeInsets.only(right: 12),
        // As tall as they need to be, under the summary, rather than
        // stretched to the height of the shelf. Stretched, every card was a
        // tall slot with a bottle floating in the middle of it and empty
        // space above and below.
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: _cardWidth,
            child: _BottleCard(
              bottle: shelf[i],
              index: i,
              units: units,
              now: now,
              onFinished: () => _finish(context, ref, shelf[i], now),
            ),
          ),
        ),
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
                child: list,
              ),
            );
          },
        ),
      ],
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
  final notes = [
    // The feed has no kind of milk of its own, and once the bottle is gone
    // this is the only place formula would still be written down.
    if (bottle.kind == BottleKind.formula) bottle.kind.label,
    if (bottle.notes?.trim() case final n? when n.isNotEmpty) n,
  ].join(' · ');

  showFeedingQuickLog(
    context,
    draft: BottleDraft(
      amountMl: bottle.amountMl,
      source:
          'From the fridge, ${bottle.kind.filledLabel.toLowerCase()} $when. '
          'Saving takes it off the shelf.',
      notes: notes.isEmpty ? null : notes,
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
    required this.index,
    required this.units,
    required this.now,
    required this.onFinished,
  });

  final FridgeBottle bottle;
  final int index;
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
        // The handle is the whole point of turning the default ones off:
        // dragging is deliberate, tapping opens the bottle, and neither can be
        // mistaken for the other.
        ReorderableDragStartListener(
          index: index,
          child: Icon(
            Icons.drag_indicator,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ),
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

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
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
          // The threshold grows with the text, since it is the text that has
          // to fit under the bottle. The short shape fills the shelf's height;
          // the tall one only takes what it needs and stands at the bottom.
          child: LayoutBuilder(
            builder: (context, c) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              // The bottle is as wide as the card and as tall as its shape
              // makes that, so its height is known before it is laid out.
              // Everything else is text, and grows with the text size.
              final bottleHeight = c.maxWidth / BottleGauge.aspectRatio;
              final tall =
                  c.maxHeight >= bottleHeight + 50 + (130 + 50) * scale;

              if (tall) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: 8),
                    gauge,
                    const SizedBox(height: 10),
                    _Facts(bottle: bottle, units: units, now: now),
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
        Text(
          FeedingFormat.clockStamp(context, bottle.filledAt, now: now),
          style: theme.textTheme.bodyMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          FeedingFormat.timeAgo(bottle.filledAt, now: now),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
