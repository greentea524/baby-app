import 'package:flutter/material.dart';

import '../../core/format/unit_system.dart';
import '../../core/format/volume_format.dart';
import '../../data/models/feeding_event.dart';
import '../timeline/timeline_format.dart';

/// Display helpers for feeding events, kept out of widgets so the timeline
/// and stats epics (KAN-132) can reuse them.
abstract final class FeedingFormat {
  static String typeLabel(FeedingType type) => switch (type) {
    FeedingType.breast => 'Breastfeeding',
    FeedingType.bottle => 'Bottle',
    FeedingType.solids => 'Solids',
  };

  /// What a logged feed is, marking a top-up as such.
  ///
  /// A snack is stored as an ordinary bottle or breast feed with `isSnack`
  /// set, so on [typeLabel] alone it reads exactly like a full one. That
  /// matters beyond tidiness: snacks are the feeds the next-feed clock
  /// deliberately ignores, so without the label a caregiver sees a feed
  /// logged ten minutes ago sitting under a countdown measured from an
  /// earlier one, with nothing to explain the difference.
  static String eventLabel(FeedingEvent e) =>
      e.isSnack ? '${typeLabel(e.type)} · Snack' : typeLabel(e.type);

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

  /// A compact one-line detail for an event, e.g. "18 min · Left" or
  /// "120 ml (4.1 fl oz)", in the caregiver's [units].
  static String details(FeedingEvent e, UnitSystem units) {
    final parts = <String>[];
    if (e.durationMinutes != null) parts.add('${e.durationMinutes} min');
    if (e.side != null) parts.add(sideLabel(e.side!));
    if (e.amountMl != null) parts.add(formatVolume(e.amountMl!, units));
    if (e.notes != null && e.notes!.trim().isNotEmpty) {
      parts.add(e.notes!.trim());
    }
    return parts.join(' · ');
  }

  /// Coarse "time ago" string: "just now", "23 min ago", "3 hr 5 min ago",
  /// "2 days ago". Within the first day, hours carry the trailing minutes so
  /// feed intervals read precisely. [now] is injectable for testing.
  static String timeAgo(DateTime time, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      return m == 0 ? '$h hr ago' : '$h hr $m min ago';
    }
    final d = diff.inDays;
    return d == 1 ? '1 day ago' : '$d days ago';
  }

  /// The absolute time an entry was logged, to sit alongside the relative
  /// "x ago" label: just the clock time for today, prefixed with a short date
  /// otherwise so older rows aren't ambiguous.
  ///
  /// Takes a [BuildContext] so the clock follows the device's 12/24-hour
  /// setting. [now] is injectable for testing.
  static String clockStamp(
    BuildContext context,
    DateTime time, {
    DateTime? now,
  }) {
    final clock = TimeOfDay.fromDateTime(time).format(context);
    if (TimelineFormat.isSameDay(time, now ?? DateTime.now())) return clock;
    return '${TimelineFormat.shortDate(time)}, $clock';
  }

  /// mm:ss for a running or recorded stopwatch duration.
  static String stopwatch(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
