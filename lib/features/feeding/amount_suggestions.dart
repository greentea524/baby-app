import '../../core/format/volume_format.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/pumping_event.dart';

/// Where a suggested amount came from (#31).
enum AmountSource {
  /// A volume this baby is regularly given.
  bottle,

  /// The yield of a recent pump that has not been fed yet — what is in the
  /// fridge right now.
  pump,
}

/// A tappable amount offered beneath the bottle form's volume field.
class AmountSuggestion {
  const AmountSuggestion(this.millilitres, this.source);

  final double millilitres;
  final AmountSource source;

  @override
  bool operator ==(Object other) =>
      other is AmountSuggestion &&
      other.millilitres == millilitres &&
      other.source == source;

  @override
  int get hashCode => Object.hash(millilitres, source);

  @override
  String toString() => '${formatMl(millilitres)}ml/${source.name}';
}

/// Past bottles are grouped to the nearest [_binMl] before being counted.
///
/// Real entries scatter: 118, 120 and 122 are one habit typed three ways, and
/// counted apart they offer the same feed three times over.
///
/// Grouping only. What the chip then *shows* is one of the amounts actually
/// recorded in the group — see [_rankedBottleAmounts] — never the bin's own
/// round number. A chip is a thing you tap to log a volume, so a chip reading
/// 120 when every bottle in that group was 118 would log milk nobody poured.
///
/// Millilitres even when the field is showing fluid ounces. The bins have to
/// land on the numbers actually poured — snapping to the nearest half ounce
/// would group 118 and 133 together, and that drift lands in every daily
/// total on the insights table.
const double _binMl = 5;

double _bin(double ml) => (ml / _binMl).round() * _binMl;

/// How many pump sessions get a reserved chip.
///
/// Two, because a bottle is often poured from the last session while the one
/// before it is still in the fridge, and which of them you reach for is not
/// something the app can know. One chip made that a guess.
const int _pumpSlots = 2;

/// Amounts worth offering as one-tap shortcuts, smallest first.
///
/// Two sources answering two different questions. Past bottles say what this
/// baby usually drinks — a settled pattern, best read by frequency. Recent
/// pumps say what is physically in the fridge, which bottle history can never
/// know: you pump 130, you pour 130, and that feed has not been logged yet.
///
/// They are deliberately not ranked together. A pump session against forty
/// bottles loses every frequency contest, so a single pot would always drop
/// the freshest numbers. Pumps get [_pumpSlots] reserved places instead.
///
/// Every amount offered is one that was actually recorded. Bottle history is
/// grouped to bins to be counted, but a chip carries a real entry's volume
/// rather than its bin — tapping a chip logs the number on it, so a rounded
/// one would put milk nobody poured into the record.
///
/// At most [max] of them. Five rather than three: a baby's day is rarely one
/// volume, and the chips are only worth having when the amount you want is
/// already on the row. They wrap onto a second line on a narrow sheet, which
/// costs less than typing.
///
/// Handles unsorted input; [feeds] and [pumps] need not be in any order.
List<AmountSuggestion> suggestedAmounts({
  required List<FeedingEvent> feeds,
  required List<PumpingEvent> pumps,
  int max = 5,
}) {
  if (max <= 0) return const [];

  // Snacks are excluded: a top-up is small by definition, and letting one
  // into the ranking drags the ladder below any real feed.
  final bottles =
      feeds
          .where(
            (f) =>
                f.type == FeedingType.bottle &&
                f.amountMl != null &&
                !f.isSnack,
          )
          .toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

  final picked = <AmountSuggestion>[];
  // Which bins the pump chips have spoken for. Compared by bin rather than
  // by exact value: a 122 ml pump beside a 120 ml bottle chip is two chips
  // for one pour, and the difference between them is not a choice anyone is
  // making.
  final spokenFor = <double>{};

  for (final ml in _milkInHandMl(pumps, bottles)) {
    if (picked.length >= max) break;
    picked.add(AmountSuggestion(ml, AmountSource.pump));
    spokenFor.add(_bin(ml));
  }

  for (final ml in _rankedBottleAmounts(bottles)) {
    if (picked.length >= max) break;
    // The pump-marked chip already says more about where it came from.
    if (spokenFor.contains(_bin(ml))) continue;
    picked.add(AmountSuggestion(ml, AmountSource.bottle));
  }

  picked.sort((a, b) => a.millilitres.compareTo(b.millilitres));
  return picked;
}

/// The yields still standing in the fridge, most recent first, at most
/// [_pumpSlots] of them.
///
/// A session counts only while it postdates the last bottle. Milk pumped at
/// seven and given at nine is not what you are holding at two, and offering
/// it then is worse than offering nothing — so a feed logged after a session
/// takes that session off the row and leaves the ones that have not been
/// poured yet. Everything older than the last bottle is older still, which
/// is why the same one test settles every session.
///
/// With no bottles logged at all they all qualify — a household pouring its
/// first bottle has nothing else to go on, which is exactly when the
/// suggestion is most useful.
///
/// Exact, never binned. This is the one number on the row that is a
/// measurement rather than a habit: a 93 ml session offered as 95 is milk
/// that was never in the bottle, and the chip exists to save typing the
/// amount, not to change it.
///
/// Two sessions that came back at the same volume are one chip. The second
/// would be indistinguishable from the first and tap to the same number.
List<double> _milkInHandMl(
  List<PumpingEvent> pumps,
  List<FeedingEvent> bottles,
) {
  final lastBottle = bottles.isEmpty ? null : bottles.first.startTime;
  final inHand =
      pumps
          .where(
            (p) =>
                p.amountMl != null &&
                p.amountMl! > 0 &&
                (lastBottle == null || p.time.isAfter(lastBottle)),
          )
          .toList()
        ..sort((a, b) => b.time.compareTo(a.time));

  final out = <double>[];
  for (final p in inHand) {
    if (out.length >= _pumpSlots) break;
    if (out.contains(p.amountMl!)) continue;
    out.add(p.amountMl!);
  }
  return out;
}

/// Amounts in the order they are worth offering: the most often poured group
/// first, and between two equally common ones the more recent, so a rhythm
/// that is changing moves the chips rather than being outvoted by history.
///
/// Counted by bin, offered by entry. Each group contributes the volume of
/// its most recently poured bottle, which is a number this household has
/// actually used — 118, 120 and 122 are one chip, and that chip reads
/// whichever of them was poured last rather than a tidied 120.
///
/// Most recent rather than, say, the commonest within the group, for the
/// reason the tie-break above exists: where a household's amounts are
/// drifting, the latest one is the one being poured now.
List<double> _rankedBottleAmounts(List<FeedingEvent> bottles) {
  final counts = <double, int>{};
  final latest = <double, DateTime>{};
  final offer = <double, double>{};
  for (final b in bottles) {
    final ml = _bin(b.amountMl!);
    // A few millilitres round away to nothing, and a chip reading 0 is worse
    // than one chip fewer.
    if (ml <= 0) continue;
    counts[ml] = (counts[ml] ?? 0) + 1;
    final seen = latest[ml];
    if (seen == null || b.startTime.isAfter(seen)) {
      latest[ml] = b.startTime;
      offer[ml] = b.amountMl!;
    }
  }

  final bins = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : latest[b]!.compareTo(latest[a]!);
    });
  return [for (final bin in bins) offer[bin]!];
}
