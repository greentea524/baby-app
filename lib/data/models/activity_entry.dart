import 'diaper_event.dart';
import 'feeding_event.dart';

/// A single item in a unified feed/diaper activity stream. Lets the home
/// recent list and the daily timeline (KAN-132) render both event types
/// through one sorted list.
sealed class ActivityEntry {
  const ActivityEntry();

  DateTime get time;
}

class FeedingEntry extends ActivityEntry {
  const FeedingEntry(this.event);

  final FeedingEvent event;

  @override
  DateTime get time => event.startTime;
}

class DiaperEntry extends ActivityEntry {
  const DiaperEntry(this.event);

  final DiaperEvent event;

  @override
  DateTime get time => event.time;
}

/// Merges feedings and diapers into one time-sorted list.
List<ActivityEntry> mergeActivities(
  List<FeedingEvent> feedings,
  List<DiaperEvent> diapers, {
  bool descending = true,
}) {
  final entries = <ActivityEntry>[
    ...feedings.map(FeedingEntry.new),
    ...diapers.map(DiaperEntry.new),
  ];
  entries.sort(
    (a, b) => descending ? b.time.compareTo(a.time) : a.time.compareTo(b.time),
  );
  return entries;
}
