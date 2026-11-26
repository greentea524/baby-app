import 'care_stay.dart';
import 'daily_check.dart';
import 'diaper_event.dart';
import 'feeding_event.dart';
import 'medication_event.dart';
import 'pumping_event.dart';

/// A single item in a unified activity stream (feed / diaper / pump /
/// medicine / checklist tick). Lets the home recent list and the daily timeline (KAN-132)
/// render every event type through one sorted list.
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

class PumpingEntry extends ActivityEntry {
  const PumpingEntry(this.event);

  final PumpingEvent event;

  @override
  DateTime get time => event.time;
}

class MedicationEntry extends ActivityEntry {
  const MedicationEntry(this.event);

  final MedicationEvent event;

  @override
  DateTime get time => event.time;
}

/// An item ticked off the daily checklist.
class CheckEntry extends ActivityEntry {
  const CheckEntry(this.event);

  final DailyCheck event;

  @override
  DateTime get time => event.time;
}

/// A drop-off, or the pick-up that ended it: one stay is two entries, each
/// at its own time.
class StayEntry extends ActivityEntry {
  const StayEntry(this.stay, {this.pickUp = false});

  final CareStay stay;

  /// The pick-up rather than the drop-off.
  final bool pickUp;

  @override
  DateTime get time => pickUp ? stay.pickedUpAt! : stay.droppedAt;
}

/// Merges feedings, diapers, pump sessions, doses of medicine and checklist
/// ticks into one time-sorted list.
List<ActivityEntry> mergeActivities(
  List<FeedingEvent> feedings,
  List<DiaperEvent> diapers, {
  List<PumpingEvent> pumps = const [],
  List<MedicationEvent> meds = const [],
  List<DailyCheck> checks = const [],
  List<CareStay> stays = const [],
  bool descending = true,
}) {
  final entries = <ActivityEntry>[
    ...feedings.map(FeedingEntry.new),
    ...diapers.map(DiaperEntry.new),
    ...pumps.map(PumpingEntry.new),
    ...meds.map(MedicationEntry.new),
    ...checks.map(CheckEntry.new),
    for (final stay in stays) ...[
      StayEntry(stay),
      if (stay.pickedUpAt != null) StayEntry(stay, pickUp: true),
    ],
  ];
  entries.sort(
    (a, b) => descending ? b.time.compareTo(a.time) : a.time.compareTo(b.time),
  );
  return entries;
}
