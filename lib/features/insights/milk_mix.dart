import '../../data/models/milk_kind.dart';

/// How a stretch of bottle feeds splits by what was in them, in millilitres,
/// and how that sets against what was pumped.
///
/// Bottles only. A breastfeed has minutes and no volume, so it cannot share a
/// scale in millilitres with anything here; it is left out rather than
/// guessed at, and the charts built on this say "bottles" to be clear about
/// it.
///
/// [unknownMl] is bottle milk logged before feeds recorded their milk. It is
/// never folded into breast milk: an old feed of formula counted as breast
/// milk would make the one figure this exists for — how much of it was
/// pumped milk — say more than was true.
class MilkMix {
  const MilkMix({
    this.breastMilkMl = 0,
    this.formulaMl = 0,
    this.wholeMilkMl = 0,
    this.unknownMl = 0,
  });

  /// Adds up bottle volumes by milk, from [byMilk] as `DayStats` keeps it —
  /// null for an unrecorded milk.
  factory MilkMix.of(Map<MilkKind?, double> byMilk) => MilkMix(
    breastMilkMl: byMilk[MilkKind.expressed] ?? 0,
    formulaMl: byMilk[MilkKind.formula] ?? 0,
    wholeMilkMl: byMilk[MilkKind.wholeMilk] ?? 0,
    unknownMl: byMilk[null] ?? 0,
  );

  final double breastMilkMl;
  final double formulaMl;
  final double wholeMilkMl;
  final double unknownMl;

  double get totalMl => breastMilkMl + formulaMl + wholeMilkMl + unknownMl;

  /// Millilitres of [kind], or of unrecorded milk for null.
  double ml(MilkKind? kind) => switch (kind) {
    MilkKind.expressed => breastMilkMl,
    MilkKind.formula => formulaMl,
    MilkKind.wholeMilk => wholeMilkMl,
    null => unknownMl,
  };

  /// [kind]'s share of every bottle, 0 to 1; 0 when there were none.
  double share(MilkKind? kind) => totalMl == 0 ? 0 : ml(kind) / totalMl;

  /// What was pumped, as a fraction of the breast milk fed from bottles.
  ///
  /// Above 1, pumping is ahead and the difference is going into the fridge;
  /// below it, bottles of breast milk are drawing on milk pumped before the
  /// window began. Null with no breast milk fed, where there is nothing to
  /// measure against — not "infinitely ahead".
  ///
  /// Over a single day this moves a lot, because milk pumped in the evening
  /// is often drunk the next morning; over a week it settles.
  double? pumpCoverage(double pumpedMl) =>
      breastMilkMl == 0 ? null : pumpedMl / breastMilkMl;
}
