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
  /// "120 ml (4.1 fl oz) · Formula", in the caregiver's [units].
  static String details(FeedingEvent e, UnitSystem units) {
    final parts = <String>[];
    if (e.durationMinutes != null) parts.add('${e.durationMinutes} min');
    if (e.side != null) parts.add(sideLabel(e.side!));
    if (e.amountMl != null) parts.add(formatVolume(e.amountMl!, units));
    if (e.milk != null) parts.add(e.milk!.label);
    if (e.notes != null && e.notes!.trim().isNotEmpty) {
      parts.add(e.notes!.trim());
    }
    return parts.join(' · ');
  }

  /// Everything [details] says that [measure] does not: the side, the milk,
  /// the notes, and the duration when an amount is the measure.
  ///
  /// For Home, which puts the measure in the row's headline beside what
  /// the feed was, and these on the muted line underneath.
  static String extras(FeedingEvent e, UnitSystem units) {
    final notes = e.notes?.trim() ?? '';
    return [
      if (e.durationMinutes != null && e.amountMl != null)
        '${e.durationMinutes} min',
      if (e.side != null) sideLabel(e.side!),
      if (e.milk != null) e.milk!.label,
      if (notes.isNotEmpty) notes,
    ].join(' · ');
  }

  /// The measured part of a feed on its own — the volume, or the time spent
  /// at the breast — and null when the feed carries neither.
  ///
  /// Narrower than [details] on purpose. Nursery mode is read from across a
  /// room at boosted text size, and a note is a sentence: one would push the
  /// number it sits beside off the card entirely.
  static String? measure(FeedingEvent e, UnitSystem units) {
    if (e.amountMl != null) return formatVolume(e.amountMl!, units);
    if (e.durationMinutes != null) return '${e.durationMinutes} min';
    return null;
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

  /// [timeAgo] in fewer characters: "just now", "15m ago", "2h 20m ago",
  /// "3 days ago".
  ///
  /// For Home's time column, which lines every row's elapsed time up down
  /// the right edge: at "3 hr 5 min ago" the column was wide enough to
  /// squeeze what happened into an ellipsis.
  static String shortAgo(DateTime time, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      return m == 0 ? '${h}h ago' : '${h}h ${m}m ago';
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
