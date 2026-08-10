import 'package:flutter/material.dart';

import '../../data/models/diaper_event.dart';

/// Display helpers for diaper events, mirroring FeedingFormat.
abstract final class DiaperFormat {
  static String typeLabel(DiaperType type) => switch (type) {
    DiaperType.wet => 'Wet',
    DiaperType.dirty => 'Dirty',
    DiaperType.both => 'Wet + Dirty',
  };

  static IconData typeIcon(DiaperType type) => switch (type) {
    DiaperType.wet => Icons.water_drop,
    DiaperType.dirty => Icons.eco,
    DiaperType.both => Icons.change_circle,
  };

  /// Size then notes, joined so a row reads as one thing — "Large · green,
  /// runny" — rather than as two fields competing for the same line
  /// (#20, KAN-149).
  static String details(DiaperEvent e) {
    final notes = e.notes?.trim() ?? '';
    return [
      if (e.size != null) e.size!.label,
      if (notes.isNotEmpty) notes,
    ].join(' · ');
  }
}
