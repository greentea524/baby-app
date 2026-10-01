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
/// letter, which only two devices saving at once can do, the older keeps it
/// and the newer goes to Other.
ShelfLayout layoutShelf(List<FridgeBottle> bottles) {
  final labelled = <FridgeSlot, FridgeBottle>{};
  final other = <FridgeBottle>[];
  final toSave = <String, FridgeSlot>{};

  final byAge = [...bottles]..sort((a, b) => a.filledAt.compareTo(b.filledAt));
  for (final b in byAge) {
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

  other.sort((a, b) => a.filledAt.compareTo(b.filledAt));
  return ShelfLayout(labelled: labelled, other: other, toSave: toSave);
}
