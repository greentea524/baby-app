import '../../data/models/feeding_event.dart';
import '../../data/models/pumping_event.dart';

/// Where a suggested amount came from (#31).
enum AmountSource {
  /// A volume this baby is regularly given.
  bottle,

  /// The yield of the most recent pump — what is in the fridge right now.
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
  String toString() => '${millilitres.toStringAsFixed(0)}ml/${source.name}';
}

/// Amounts are grouped to the nearest [_binMl] before being counted.
///
/// Real entries scatter: 118, 120 and 125 are one habit typed three ways, and
/// counted apart they offer the same feed three times over.
///
/// Millilitres even when the field is showing fluid ounces. The bins have to
/// land on the numbers actually poured — snapping to the nearest half ounce
/// would read more tidily but store 118.3 where the household means 120, and
/// that drift lands in every daily total on the insights table.
const double _binMl = 10;

double _bin(double ml) => (ml / _binMl).round() * _binMl;

/// Amounts worth offering as one-tap shortcuts, smallest first.
///
/// Two sources answering two different questions. Past bottles say what this
/// baby usually drinks — a settled pattern, best read by frequency. The last
/// pump says what is physically in the bottle, which bottle history can never
/// know: you pump 130, you pour 130, and that feed has not been logged yet.
///
/// They are deliberately not ranked together. One pump session against forty
/// bottles loses every frequency contest, so a single pot would always drop
/// the freshest number. The pump gets a reserved place instead.
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

  final pumpMl = _milkInHandMl(pumps, bottles);
  final picked = <AmountSuggestion>[
    if (pumpMl != null) AmountSuggestion(pumpMl, AmountSource.pump),
  ];

  for (final ml in _rankedBottleBins(bottles)) {
    if (picked.length >= max) break;
    // The same number twice helps nobody; the pump-marked one already says
    // more about where it came from.
    if (ml == pumpMl) continue;
    picked.add(AmountSuggestion(ml, AmountSource.bottle));
  }

  picked.sort((a, b) => a.millilitres.compareTo(b.millilitres));
  return picked;
}

/// The latest pump's yield, but only while it is still the milk in hand.
///
/// It has to postdate the last bottle. Milk pumped at seven and given at nine
/// is not what you are holding at two, and offering it then is worse than
/// offering nothing. With no bottles logged at all it always qualifies — a
/// household pouring its first bottle has nothing else to go on, which is
/// exactly when the suggestion is most useful.
double? _milkInHandMl(List<PumpingEvent> pumps, List<FeedingEvent> bottles) {
  PumpingEvent? latest;
  for (final p in pumps) {
    if (p.amountMl == null) continue;
    if (latest == null || p.time.isAfter(latest.time)) latest = p;
  }
  if (latest == null) return null;
  if (bottles.isNotEmpty && !latest.time.isAfter(bottles.first.startTime)) {
    return null;
  }
  final ml = _bin(latest.amountMl!);
  return ml > 0 ? ml : null;
}

/// Bins in the order they are worth offering: most often poured first, and
/// between two equally common ones the more recent, so a rhythm that is
/// changing moves the chips rather than being outvoted by history.
List<double> _rankedBottleBins(List<FeedingEvent> bottles) {
  final counts = <double, int>{};
  final latest = <double, DateTime>{};
  for (final b in bottles) {
    final ml = _bin(b.amountMl!);
    // A few millilitres round away to nothing, and a chip reading 0 is worse
    // than one chip fewer.
    if (ml <= 0) continue;
    counts[ml] = (counts[ml] ?? 0) + 1;
    final seen = latest[ml];
    if (seen == null || b.startTime.isAfter(seen)) latest[ml] = b.startTime;
  }

  return counts.keys.toList()..sort((a, b) {
    final byCount = counts[b]!.compareTo(counts[a]!);
    return byCount != 0 ? byCount : latest[b]!.compareTo(latest[a]!);
  });
}
