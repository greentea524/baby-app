import 'dart:async';

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
import 'fridge_slots.dart';

/// What bottles are in the fridge, laid out the way the fridge is.
///
/// Three labelled slots, A, B and C, then everything else under Other. Fixed
/// places rather than an order: when the bottle in A is used, the others
/// stay where they are, so A shows empty and the letters on screen keep
/// matching the ones on the shelf. A new bottle takes the first empty
/// letter.
///
/// Its own screen rather than a card on Home. Home answers "when did that last
/// happen"; this answers "what have I got", which is a different question and
/// a longer answer.
class FridgeScreen extends ConsumerStatefulWidget {
  const FridgeScreen({super.key, this.now});

  /// A fixed clock, for tests. Every card reads "3 hr ago", which is measured
  /// from somewhere.
  final DateTime? now;

  @override
  ConsumerState<FridgeScreen> createState() => _FridgeScreenState();
}

class _FridgeScreenState extends ConsumerState<FridgeScreen> {
  /// Bottles whose worked-out place has been sent to be stored, so a rebuild
  /// before the write comes back does not send it again.
  final _placing = <String>{};

  /// Stores the places the layout had to work out — bottles that arrived
  /// without a slot — so every device draws the same fridge. After the frame,
  /// never during it.
  void _storePlaces(ShelfLayout layout) {
    final fresh = {
      for (final MapEntry(:key, :value) in layout.toSave.entries)
        if (!_placing.contains(key)) key: value,
    };
    if (fresh.isEmpty) return;
    _placing.addAll(fresh.keys);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo = ref.read(fridgeRepositoryProvider);
      if (repo == null || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      unawaited(
        Future.sync(() => repo.place(fresh)).catchError((Object e) {
          // Said, not swallowed: an unsaved place is drawn here but not on
          // anyone else's phone, which is exactly the mismatch it is for.
          // Let go of the ids so the next build tries again.
          _placing.removeAll(fresh.keys);
          messenger.showSnackBar(
            SnackBar(content: Text('Could not save the fridge slots: $e')),
          );
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(fridgeLayoutProvider);
    final shelf = layout.inOrder;
    _storePlaces(layout);
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
    void add([FridgeSlot? slot]) => showBottleSheet(
      context,
      slot: slot,
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
        child: layout.count == 0
            ? const _EmptyFridge()
            : _Shelf(
                layout: layout,
                now: widget.now ?? DateTime.now(),
                onAdd: add,
              ),
      ),
    );
  }
}

class _Shelf extends ConsumerWidget {
  const _Shelf({required this.layout, required this.now, required this.onAdd});

  final ShelfLayout layout;
  final DateTime now;

  /// Opens the add sheet on a given empty slot.
  final void Function(FridgeSlot slot) onAdd;

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
    final shelf = layout.inOrder;
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
            'Bottles stay in their slot. Drag one by its handle to move it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    // A failed move puts the bottle back where it was on this screen, and
    // never reaches anyone else's — so it says so, rather than leaving two
    // phones quietly disagreeing.
    void move(FridgeBottle bottle, FridgeSlot slot) {
      final repo = ref.read(fridgeRepositoryProvider);
      if (repo == null) return;
      final messenger = ScaffoldMessenger.of(context);
      unawaited(
        Future.sync(() => repo.moveTo(bottle, slot, layout: layout)).catchError(
          (Object e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not move the bottle: $e')),
            );
          },
        ),
      );
    }

    Widget card(FridgeBottle b) => _BottleCard(
      bottle: b,
      units: units,
      now: now,
      onFinished: () => _finish(context, ref, b, now),
    );

    final columns = <Widget>[
      for (final slot in FridgeSlot.labelled)
        _SlotColumn(
          key: ValueKey(slot),
          slot: slot,
          bottle: layout.labelled[slot],
          onDrop: (b) => move(b, slot),
          child: switch (layout.labelled[slot]) {
            final b? => card(b),
            null => _EmptySlot(slot: slot, onAdd: () => onAdd(slot)),
          },
        ),
      for (final b in layout.other)
        _SlotColumn(
          key: ValueKey(b.id),
          slot: FridgeSlot.other,
          bottle: b,
          onDrop: (dropped) => move(dropped, FridgeSlot.other),
          child: card(b),
        ),
    ];

    // The shelf takes a height rather than wrapping its cards: a fixed-height
    // band is what a shelf looks like, and the cards lay themselves out to
    // it.
    final list = ListView.separated(
      scrollDirection: Axis.horizontal,
      // Clear of the Add button at the bottom. Without the gap it sat
      // over the last card, on top of the very lines that say when that
      // bottle was pumped.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: columns.length,
      separatorBuilder: (_, i) =>
          // A wider gap, and a rule, where the letters end and Other begins.
          i == FridgeSlot.labelled.length - 1
          ? const _OtherDivider()
          : const SizedBox(width: 12),
      itemBuilder: (context, i) =>
          SizedBox(width: _cardWidth, child: columns[i]),
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

/// One place on the shelf: its label above, and what is in it below.
///
/// A drop target too. A bottle dragged here moves here, and if a bottle is
/// already here the two swap — the same as choosing the slot in the
/// bottle's sheet.
class _SlotColumn extends StatelessWidget {
  const _SlotColumn({
    super.key,
    required this.slot,
    required this.bottle,
    required this.onDrop,
    required this.child,
  });

  final FridgeSlot slot;

  /// What is here now, or null for an empty slot.
  final FridgeBottle? bottle;
  final void Function(FridgeBottle) onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<FridgeBottle>(
      onWillAcceptWithDetails: (d) => d.data.id != bottle?.id,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SlotLabel(slot: slot),
              const SizedBox(height: 6),
              // As tall as it needs to be, under the label, rather than
              // stretched to the height of the shelf.
              Flexible(
                child: Align(alignment: Alignment.topCenter, child: child),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "A", large enough to match against a label on the fridge door; "Other"
/// in a quieter weight and colour, since it names an area rather than a
/// place.
class _SlotLabel extends StatelessWidget {
  const _SlotLabel({required this.slot});

  final FridgeSlot slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: slot.isLabelled ? 'Slot ${slot.label}' : 'Other',
      excludeSemantics: true,
      child: Text(
        slot.label,
        textAlign: TextAlign.center,
        maxLines: 1,
        // One size for both, quieter for Other. A smaller "Other" left its
        // cards a few points taller than the lettered ones, which tipped
        // them into a different card shape side by side.
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: slot.isLabelled ? FontWeight.w700 : FontWeight.w400,
          color: slot.isLabelled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A lettered slot with nothing in it: kept on screen, because the space on
/// the shelf is still there.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.slot, required this.onAdd});

  final FridgeSlot slot;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Empty',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add here'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The break between the lettered slots and Other.
class _OtherDivider extends StatelessWidget {
  const _OtherDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
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
        // Dragged from the handle only: dragging is deliberate, tapping
        // opens the bottle, and neither can be mistaken for the other. Drop
        // it on another slot to move it there.
        Draggable<FridgeBottle>(
          data: bottle,
          feedback: _DragFeedback(bottle: bottle, units: units),
          childWhenDragging: Icon(
            Icons.drag_indicator,
            size: 20,
            color: scheme.outlineVariant,
          ),
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

    // Yellow from two days, red from three: the same amber and red Home
    // uses for something coming due, so the two read as one warning. The
    // whole card is tinted, since it is the bottle that is getting old; the
    // age line inside says it in words too.
    final age = BottleAge.of(bottle.filledAt, now);
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
              // The drink-by label and date are the last 48 of them.
              final textHeight = 50 + (152 + 76) * scale;
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

/// What follows the finger while a bottle is dragged: small, so the slot
/// it is over stays visible.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.bottle, required this.units});

  final FridgeBottle bottle;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: BottleGauge(amountMl: bottle.amountMl, kind: bottle.kind),
            ),
            const SizedBox(width: 8),
            Text(
              formatVolume(bottle.amountMl, units),
              style: theme.textTheme.titleSmall,
            ),
          ],
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
