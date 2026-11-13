import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/repositories/repository_providers.dart';
import '../feeding/feeding_format.dart';
import '../feeding/feeding_quick_log.dart';
import '../home/home_prefs.dart';

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
void finishBottle(
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
          Future.sync(() => repo.finish(bottle)).catchError((Object e) {
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

/// "Finished up next · 90 ml": the bottle up next, fed, in one tap from
/// wherever the feed is being given — Home, the nursery — as its Finished
/// button does on the fridge's shelf. Nothing while none is up next, or
/// with the fridge switched off.
class UpNextButton extends ConsumerWidget {
  const UpNextButton({super.key, this.now});

  /// A fixed clock, for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showFridgeProvider)) return const SizedBox.shrink();
    final next = upNext(ref.watch(fridgeShelfProvider));
    if (next == null) return const SizedBox.shrink();
    final units = ref.watch(unitSystemProvider);
    // Filled in the app's colour and only as wide as its words: in the
    // countdowns' pale tint and at their full width, as it was, it read as
    // one more of them and not as something to press.
    return FilledButton.icon(
      key: const ValueKey('up-next-finished'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      onPressed: () => finishBottle(context, ref, next, now ?? DateTime.now()),
      icon: const Icon(Icons.check, size: 18),
      label: Text(
        'Finished up next · ${formatVolume(next.amountMl, units)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
