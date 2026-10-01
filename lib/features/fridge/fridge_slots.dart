import '../../data/models/fridge_bottle.dart';
import 'fridge_order.dart';

/// The fridge as it stands: who is in A, B and C, and what is in Other.
class ShelfLayout {
  const ShelfLayout({
    required this.labelled,
    required this.other,
    required this.toSave,
  });

  /// The bottle in each labelled slot. A slot missing from the map is empty.
  final Map<FridgeSlot, FridgeBottle> labelled;

  /// Everything past the labelled slots, oldest first.
  final List<FridgeBottle> other;

  /// Places worked out here that are not stored yet — bottles that arrived
  /// without one, and the loser of two bottles stored in the same slot.
  /// Saved once, so every device draws the same fridge.
  final Map<String, FridgeSlot> toSave;

  /// Where [bottle] stands, or null if it is not on this shelf.
  FridgeSlot? slotOf(FridgeBottle bottle) {
    for (final MapEntry(:key, :value) in labelled.entries) {
      if (value.id == bottle.id) return key;
    }
    return other.any((b) => b.id == bottle.id) ? FridgeSlot.other : null;
  }

  /// Where a new bottle goes: the first empty letter, else Other.
  FridgeSlot get firstFree => FridgeSlot.labelled.firstWhere(
    (s) => !labelled.containsKey(s),
    orElse: () => FridgeSlot.other,
  );

  /// Every bottle in the order it is reached for: A, B, C, then Other.
  List<FridgeBottle> get inOrder => [
    for (final s in FridgeSlot.labelled) ?labelled[s],
    ...other,
  ];

  int get count => labelled.length + other.length;
}

/// Lays [bottles] out in their slots.
///
/// A stored slot is kept. A bottle without one — saved before slots existed,
/// or by an app that does not know them — goes in the first empty letter, in
/// the order the shelf used to show (by hand, if it had been arranged, so
/// the first three land where they were). If two bottles claim the same
/// letter, which only two devices saving at once can do, the one that was
/// put there first keeps it and the other goes to Other.
ShelfLayout layoutShelf(List<FridgeBottle> bottles) {
  final labelled = <FridgeSlot, FridgeBottle>{};
  final other = <FridgeBottle>[];
  final toSave = <String, FridgeSlot>{};

  // Claims are settled in the order they were made. It used to be by the
  // milk's age, and a pumped bottle carries its pump time — so one placed
  // into a letter another device had just filled took it over, and the
  // bottle already there was pushed to Other.
  final byClaim = [...bottles]..sort(_byClaim);
  for (final b in byClaim) {
    switch (b.slot) {
      case final slot? when slot.isLabelled:
        if (labelled.containsKey(slot)) {
          other.add(b);
          toSave[b.id] = FridgeSlot.other;
        } else {
          labelled[slot] = b;
        }
      case FridgeSlot.other:
        other.add(b);
      default:
        break;
    }
  }

  for (final b in shelfOrder(bottles)) {
    if (b.slot != null) continue;
    final free = FridgeSlot.labelled.where((s) => !labelled.containsKey(s));
    final slot = free.isEmpty ? FridgeSlot.other : free.first;
    if (slot.isLabelled) {
      labelled[slot] = b;
    } else {
      other.add(b);
    }
    toSave[b.id] = slot;
  }

  other.sort(_byAge);
  return ShelfLayout(labelled: labelled, other: other, toSave: toSave);
}

/// Earliest put in its slot first; a bottle with no record of when counts
/// as earliest, having been there since before it was recorded. Ties by id.
int _byClaim(FridgeBottle a, FridgeBottle b) {
  final at = a.slottedAt, bt = b.slottedAt;
  if (at != bt) {
    if (at == null) return -1;
    if (bt == null) return 1;
    return at.compareTo(bt);
  }
  return a.id.compareTo(b.id);
}

/// Oldest first, and between two filled at the same moment — both halves
/// of a split always are — by id. Without the tiebreak, which of the two
/// came first was down to the order each device happened to receive them
/// in, and two phones could draw Other in two different orders.
int _byAge(FridgeBottle a, FridgeBottle b) {
  final byTime = a.filledAt.compareTo(b.filledAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}
