import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/repositories/repository_providers.dart';
import '../feeding/feeding_format.dart';
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
        onPressed: () => showBottleSheet(context, prefillFrom: lastPump),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final byKind = totalByKind(shelf);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
                      .map(
                        (e) => '${e.key.label} ${formatVolume(e.value, units)}',
                      )
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
        ),
        // The shelf takes the height it is given rather than wrapping its
        // cards: a horizontal reorderable list needs a bounded cross axis,
        // and a fixed-height band is also what a shelf looks like.
        Expanded(
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
              child: SizedBox(
                width: _cardWidth,
                child: _BottleCard(
                  bottle: shelf[i],
                  index: i,
                  units: units,
                  now: now,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One bottle: how much, when it was pumped, and how old that makes it.
class _BottleCard extends StatelessWidget {
  const _BottleCard({
    required this.bottle,
    required this.index,
    required this.units,
    required this.now,
  });

  final FridgeBottle bottle;
  final int index;
  final UnitSystem units;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notes = bottle.notes?.trim() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => showBottleSheet(context, existing: bottle),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(bottle.kind.icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 4),
                  // Named, not left to the icon. Which kind a bottle is
                  // changes how long it keeps, so it is not something to
                  // infer from an 18pt glyph across a kitchen.
                  Expanded(
                    child: Text(
                      bottle.kind.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // The handle is the whole point of turning the default ones
                  // off: dragging is deliberate, tapping opens the bottle,
                  // and neither can be mistaken for the other.
                  ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // The amount is the headline: standing at the fridge, how much
              // is in the bottle is what you are reading for.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatMl(bottle.amountMl),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                units.isMetric
                    ? 'ml'
                    : 'ml · ${formatFlOz(bottle.amountMl)} fl oz',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
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
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  notes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Nothing in the fridge — which is a normal state, not a problem.
class _EmptyFridge extends StatelessWidget {
  const _EmptyFridge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
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
