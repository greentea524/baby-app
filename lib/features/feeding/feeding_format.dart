import 'package:flutter/material.dart';

import '../../core/format/volume_format.dart';
import '../../data/models/feeding_event.dart';

/// Display helpers for feeding events, kept out of widgets so the timeline
/// and stats epics (KAN-132) can reuse them.
abstract final class FeedingFormat {
  static String typeLabel(FeedingType type) => switch (type) {
    FeedingType.breast => 'Breastfeeding',
    FeedingType.bottle => 'Bottle',
    FeedingType.solids => 'Solids',
  };

  static IconData typeIcon(FeedingType type) => switch (type) {
    FeedingType.breast => Icons.child_friendly,
    FeedingType.bottle => Icons.local_drink,
    FeedingType.solids => Icons.restaurant,
  };

  static String sideLabel(BreastSide side) => switch (side) {
    BreastSide.left => 'Left',
    BreastSide.right => 'Right',
    BreastSide.both => 'Both',
  };

  /// A compact one-line detail for an event, e.g. "18 min · Left" or "120 ml".
  static String details(FeedingEvent e) {
    final parts = <String>[];
    if (e.durationMinutes != null) parts.add('${e.durationMinutes} min');
    if (e.side != null) parts.add(sideLabel(e.side!));
    if (e.amountMl != null) parts.add(formatVolume(e.amountMl!));
    if (e.notes != null && e.notes!.trim().isNotEmpty) {
      parts.add(e.notes!.trim());
    }
    return parts.join(' · ');
  }

  /// Coarse "time ago" string: "just now", "23 min ago", "3 hr ago",
  /// "2 days ago". [now] is injectable for testing.
  static String timeAgo(DateTime time, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hr ago';
    }
    final d = diff.inDays;
    return d == 1 ? '1 day ago' : '$d days ago';
  }

  /// mm:ss for a running or recorded stopwatch duration.
  static String stopwatch(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
