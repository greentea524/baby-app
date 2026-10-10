/// Sums and helpers for the fridge, and the order its shelf is shown in.
library;

import '../../data/models/feeding_event.dart';
import '../../data/models/fridge_bottle.dart';
import '../../data/models/pumping_event.dart';
import '../timeline/timeline_format.dart';

/// The bottles in shelf order, leftmost first: oldest first, the order
/// milk should be used in.
///
/// Nothing else decides it — not where a bottle was put, nor when it was
/// added. A bottle used up leaves no gap, and a new one finds its own place
/// by its age.
///
/// Between two filled at the same moment — both halves of a split always
/// are — by id. Without the tiebreak, which came first was down to the
/// order each device happened to receive them in, and two phones could
/// draw the shelf in two different orders.
List<FridgeBottle> shelfOrder(List<FridgeBottle> bottles) =>
    [...bottles]..sort((a, b) {
      final byAge = a.filledAt.compareTo(b.filledAt);
      return byAge != 0 ? byAge : a.id.compareTo(b.id);
    });

/// [kept] with [pourMl] of [poured] poured into it — all of it when
/// [pourMl] is null.
///
/// The exact sum, never rounded, the way a split's halves always add back
/// up. The older of the two times, because milk is as old as its oldest
/// part — taking the newer would make the age warnings and the drink-by
/// date say a mixed bottle is fresher than some of what is in it. That holds
/// for any amount poured: a splash of old milk makes the bottle as old as
/// the splash. Both notes, so neither is lost, and blank ones skipped.
///
/// Only for two of the same kind: see [canCombine]. Mixing kinds is a
/// feeding decision, and the result would have no honest kind to show.
FridgeBottle combined(
  FridgeBottle kept,
  FridgeBottle poured, {
  double? pourMl,
}) {
  assert(canCombine(kept, poured));
  final pour = pourMl ?? poured.amountMl;
  final notes = [
    for (final n in [kept.notes, poured.notes])
      if (n != null && n.trim().isNotEmpty) n.trim(),
  ];
  return FridgeBottle(
    id: kept.id,
    filledAt: poured.filledAt.isBefore(kept.filledAt)
        ? poured.filledAt
        : kept.filledAt,
    amountMl: kept.amountMl + pour,
    kind: kept.kind,
    notes: withHistory(
      notes.isEmpty ? null : notes.join(noteSeparator),
      combinedEntry(keptMl: kept.amountMl, pouredMl: pour),
    ),
  );
}

/// What a split leaves: [bottle] holding [firstMl], and a second bottle,
/// [siblingId], with the rest.
///
/// Both keep the original's time and kind — one pour became two
/// containers, and the milk is neither younger nor a different thing for
/// having been moved — and both say so in their notes.
({FridgeBottle kept, FridgeBottle sibling}) splitBottle(
  FridgeBottle bottle,
  double firstMl, {
  required String siblingId,
}) {
  final notes = withHistory(
    bottle.notes,
    splitEntry(totalMl: bottle.amountMl, firstMl: firstMl),
  );
  return (
    kept: bottle.copyWith(amountMl: firstMl, notes: notes),
    sibling: FridgeBottle(
      id: siblingId,
      filledAt: bottle.filledAt,
      amountMl: bottle.amountMl - firstMl,
      kind: bottle.kind,
      notes: notes,
    ),
  );
}

/// What is left of [poured] after [pourMl] of it went into another bottle,
/// saying so in its notes — or null when it was poured out entirely.
FridgeBottle? pouredRemainder(FridgeBottle poured, double pourMl) {
  final left = poured.amountMl - pourMl;
  if (left <= 0) return null;
  return poured.copyWith(
    amountMl: left,
    notes: withHistory(
      poured.notes,
      pouredOutEntry(pouredMl: pourMl, fromMl: poured.amountMl),
    ),
  );
}

// --- What happened to a bottle ----------------------------------------------
//
// Splitting and combining change a bottle's amount with nothing to say why,
// and "this was 150 ml yesterday" is the question a caregiver is left with.
// So each leaves a line in the bottle's notes: added after whatever is
// written there, so a note someone typed stays first, where the card's one
// line of notes shows it, and the history follows.
//
// In millilitres whatever the reader's units. A note is shared text read on
// every caregiver's device, and the amounts are stored in ml; a converted
// "60 ml (2 fl oz) + 40 ml (1.4 fl oz)" would also not fit the card.

/// What joins a bottle's notes: the same separator combining has always put
/// between two bottles' notes.
const noteSeparator = ' · ';

/// The longest a bottle's notes may be — the rules' cap on any free text.
const bottleNotesMax = 1000;

/// "Split from 120 ml into 60 + 60 ml": on both bottles a split leaves.
String splitEntry({required double totalMl, required double firstMl}) =>
    'Split from ${_ml(totalMl)} ml into '
    '${_ml(firstMl)} + ${_ml(totalMl - firstMl)} ml';

/// "Combined 60 + 40 ml": on the bottle poured into.
String combinedEntry({required double keptMl, required double pouredMl}) =>
    'Combined ${_ml(keptMl)} + ${_ml(pouredMl)} ml';

/// "Poured 40 of 100 ml into another bottle": on a bottle poured from that
/// still has some left. One poured out entirely is gone, and needs none.
String pouredOutEntry({required double pouredMl, required double fromMl}) =>
    'Poured ${_ml(pouredMl)} of ${_ml(fromMl)} ml into another bottle';

/// [notes] with [entry] added at the end.
///
/// Kept under [bottleNotesMax], which a bottle combined and split often
/// enough would otherwise pass — and the rules would refuse the save. The
/// oldest history goes first; the first part, normally what someone typed,
/// is kept. If even that leaves no room, the entry is left off rather than
/// the note cut.
String withHistory(String? notes, String entry) {
  final text = notes?.trim() ?? '';
  if (text.isEmpty) return entry;
  final parts = text.split(noteSeparator);
  String join() => [...parts, entry].join(noteSeparator);
  while (join().length > bottleNotesMax && parts.length > 1) {
    parts.removeAt(1);
  }
  final joined = join();
  return joined.length > bottleNotesMax ? text : joined;
}

/// "60", or "62.5": whole millilitres without a decimal point.
String _ml(double ml) =>
    ml == ml.roundToDouble() ? ml.round().toString() : ml.toStringAsFixed(1);

/// How much the pour slider moves at a time.
const double pourStepMl = 5;

/// The amounts a pour can be: every [pourStepMl] up to what [fromMl]
/// holds, and then all of it, so a bottle that is not a whole number of
/// steps can still be poured out entirely. A bottle of less than one step
/// can only be poured whole.
List<double> pourStops(double fromMl) => [
  for (var ml = pourStepMl; ml < fromMl; ml += pourStepMl) ml,
  fromMl,
];

/// The amounts the first of two bottles can be, splitting one of
/// [totalMl]: every [pourStepMl], from one step to one short of the whole.
/// The second takes the rest, odd millilitres and all, so neither is ever
/// less than a step. Empty for a bottle too small to make two.
///
/// The same 5 ml steps as [pourStops], so pouring one bottle into two moves
/// the way pouring two into one does.
List<double> splitStops(double totalMl) => [
  for (var ml = pourStepMl; ml <= totalMl - pourStepMl; ml += pourStepMl) ml,
];

/// Where a split starts: the stop nearest half, the lower one on a tie.
/// Null for a bottle too small to split.
double? defaultSplitMl(double totalMl) {
  final stops = splitStops(totalMl);
  if (stops.isEmpty) return null;
  final half = totalMl / 2;
  var best = stops.first;
  for (final ml in stops) {
    if ((ml - half).abs() < (best - half).abs()) best = ml;
  }
  return best;
}

/// How much of [poured] to pour into [kept] unless told otherwise: enough
/// to fill [kept] to a full bottle, or all of [poured] if that is less.
///
/// Topping a bottle up is what a partial pour is for, so the slider starts
/// there rather than at everything, which would overfill it. Rounded down
/// to a [pourStops] stop, so it never overfills by the rounding.
double defaultPourMl(FridgeBottle kept, FridgeBottle poured) {
  final room = bottleCapacityMl - kept.amountMl;
  if (room <= 0 || room >= poured.amountMl) return poured.amountMl;
  final stops = pourStops(poured.amountMl);
  return stops.lastWhere((ml) => ml <= room, orElse: () => stops.first);
}

/// Whether [poured] can go into [kept]: another bottle, of the same kind.
bool canCombine(FridgeBottle kept, FridgeBottle poured) =>
    kept.id != poured.id && kept.kind == poured.kind;

/// What is in the fridge altogether.
double totalMl(List<FridgeBottle> bottles) =>
    bottles.fold(0, (sum, b) => sum + b.amountMl);

/// How much of each kind, for the kinds that are actually there.
///
/// Absent rather than zero for a kind the fridge holds none of: the summary
/// line reads the keys, and "0 ml of formula" is a line about nothing.
Map<MilkKind, double> totalByKind(List<FridgeBottle> bottles) {
  final totals = <MilkKind, double>{};
  for (final b in bottles) {
    totals[b.kind] = (totals[b.kind] ?? 0) + b.amountMl;
  }
  return totals;
}

/// How much one bottle holds, full to the top mark.
///
/// One number, here, because it is one fact about the household's bottles
/// rather than about any bottle in particular. When the baby moves up to the
/// next size of bottle, this is the line that changes.
const double bottleCapacityMl = 120;

/// How full [amountMl] leaves a bottle, from 0 to 1.
///
/// Clamped at full rather than drawn spilling over. A reading over capacity
/// is a bottle bigger than this one, not an overflowing one, and the amount
/// written beside the drawing is exact either way — the drawing is for the
/// glance, the number is for the record.
double fullness(double amountMl) =>
    (amountMl / bottleCapacityMl).clamp(0.0, 1.0);

/// Whether milk pumped at [pumpedAt] has gone into a bottle on [shelf].
///
/// Read off the times: a breast-milk bottle filled at or after the session,
/// and before the next one, is that session's milk. A bottle used to carry
/// its session's own time, and was matched on it; it is now stamped when it
/// goes in the fridge, which is after the session, so the match is a window
/// rather than a moment. Bottles from before the change carry the session's
/// time and still land in it.
///
/// [nextPumpAt] closes the window. Without it, for the latest session, any
/// later bottle counts — there is no later milk it could be.
///
/// To the minute, since a time picked by hand has no seconds. Breast milk
/// only: formula made up after a session is not that session's milk.
bool isBottled(
  DateTime pumpedAt,
  List<FridgeBottle> shelf, {
  DateTime? nextPumpAt,
}) {
  DateTime minute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);
  final from = minute(pumpedAt);
  final until = nextPumpAt == null ? null : minute(nextPumpAt);
  return shelf.any((b) {
    if (b.kind != MilkKind.expressed) return false;
    final at = minute(b.filledAt);
    return !at.isBefore(from) && (until == null || at.isBefore(until));
  });
}

/// The last pump session, while its milk is still to be accounted for:
/// neither bottled nor given as a feed since.
///
/// What a new fridge bottle's amount is filled in from. Both tests, because
/// either way the milk is gone: into a bottle already on the shelf, or into
/// the baby — and a finished fridge bottle is logged as a feed, so that one
/// is caught here too, where the shelf no longer shows it.
PumpingEvent? unbottledPump(
  PumpingEvent? last, {
  required List<FridgeBottle> shelf,
  required List<FeedingEvent> feeds,
}) {
  if (last == null || isBottled(last.time, shelf)) return null;
  final fedSince = feeds.any(
    (f) => f.type == FeedingType.bottle && f.startTime.isAfter(last.time),
  );
  return fedSince ? null : last;
}

/// How long a bottle has been in the fridge, in the three steps the shelf
/// colours it by.
enum BottleAge {
  /// Under two days.
  fresh,

  /// Two days or more: yellow, use it soon.
  aging,

  /// Three days or more: red.
  old;

  /// Two days, measured from when the bottle was filled — pumped, made up or
  /// poured — not from when it went in the fridge, because it is the milk's
  /// age that matters.
  static const agingAfter = Duration(days: 2);
  static const oldAfter = Duration(days: 3);

  static BottleAge of(DateTime filledAt, DateTime now) {
    final age = now.difference(filledAt);
    if (age >= oldAfter) return old;
    if (age >= agingAfter) return aging;
    return fresh;
  }
}

/// How long ago a bottle was filled, in hours however long it has been:
/// "33 hr 13 min ago" rather than "1 day ago".
///
/// Hours because that is how milk in a fridge is judged — "1 day ago" covers
/// anything from 24 to 47 hours, which is the difference between fine and
/// about to turn yellow. Under an hour it is minutes, as everywhere else.
String hoursAgo(DateTime filledAt, DateTime now) {
  final diff = now.difference(filledAt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  final h = diff.inHours;
  final m = diff.inMinutes.remainder(60);
  return m == 0 ? '$h hr ago' : '$h hr $m min ago';
}

/// How long a bottle may stand in the fridge before it should be drunk.
///
/// The household's rule rather than a medical one: four days from when it
/// was filled. The same for every kind, as the yellow and red are.
const int drinkWithinDays = 4;

/// When [filledAt]'s bottle should be drunk by: the same clock time,
/// [drinkWithinDays] calendar days on. Calendar days rather than 96 hours,
/// so a clock change in between does not move it by an hour.
DateTime drinkBy(DateTime filledAt) => DateTime(
  filledAt.year,
  filledAt.month,
  filledAt.day + drinkWithinDays,
  filledAt.hour,
  filledAt.minute,
);

/// Whether [filledAt]'s bottle is past its drink-by time at [now].
bool isPastDrinkBy(DateTime filledAt, DateTime now) =>
    !now.isBefore(drinkBy(filledAt));

/// The day part of a drink-by time, said the way it is read at a fridge:
/// "Today" or "Tomorrow" when it is that close, otherwise "Oct 5". [clock]
/// is the time, formatted by the caller for the device's 12- or 24-hour
/// setting.
String drinkByText(DateTime deadline, DateTime now, String clock) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(deadline.year, deadline.month, deadline.day);
  final days = day.difference(today).inDays;
  final when = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => TimelineFormat.shortDate(deadline),
  };
  return '$when, $clock';
}

/// How much of a bottle's time until [drinkBy] is left at [now], from 1 when
/// it was filled down to 0 at the deadline and after.
double drinkByRemaining(DateTime filledAt, DateTime now) =>
    _shareOfShelfLife(drinkBy(filledAt).difference(now), filledAt);

/// Where on the same scale a bottle [age] old sits: the point the bar has
/// emptied to when it turns yellow, or red.
double drinkByRemainingAt(Duration age, DateTime filledAt) => _shareOfShelfLife(
  drinkBy(filledAt).difference(filledAt.add(age)),
  filledAt,
);

double _shareOfShelfLife(Duration left, DateTime filledAt) {
  final whole = drinkBy(filledAt).difference(filledAt);
  if (whole <= Duration.zero) return 0;
  return (left.inSeconds / whole.inSeconds).clamp(0.0, 1.0);
}
