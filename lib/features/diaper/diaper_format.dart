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

  /// Notes are the only extra detail on a diaper (color/consistency, KAN-149).
  static String details(DiaperEvent e) =>
      (e.notes != null && e.notes!.trim().isNotEmpty) ? e.notes!.trim() : '';
}
