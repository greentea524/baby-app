import 'package:flutter/material.dart';

/// What is in a bottle — one standing in the fridge, or one being fed.
///
/// Worth distinguishing beyond labelling, because they do not keep the same
/// way: expressed milk sits in a fridge for days, made-up formula for hours.
/// The app does not put a number on either — how long is guidance that
/// belongs with whoever gave it, not baked into an app — but it has to at
/// least say which kind of clock a bottle is on. And on a feed, which of them
/// the baby drank is part of the record: the move from breast milk to formula
/// to whole milk is one a paediatrician asks about.
///
/// Stored by [name]. The names are what the Firestore rules accept, so a new
/// kind means a new entry there too.
enum MilkKind {
  /// Pumped. The timestamp is when it was expressed.
  expressed('Breast milk', 'Pumped', Icons.opacity),

  /// Powder and water. The timestamp is when it was mixed.
  formula('Formula', 'Made up', Icons.local_drink_outlined),

  /// Cow's milk, from around the first birthday. The timestamp is when it
  /// was poured.
  wholeMilk('Whole milk', 'Poured', Icons.local_cafe_outlined);

  const MilkKind(this.label, this.filledLabel, this.icon);

  /// What it is, for a card and a chooser.
  final String label;

  /// What a bottle's timestamp means. "Pumped 11:00" and "Made up 11:00" are
  /// different facts, and a bottle that says the wrong one is worse than one
  /// that says neither.
  final String filledLabel;

  final IconData icon;

  /// Expressed for anything stored before other kinds were supported, and for
  /// a value this version does not recognise. It is the commoner kind and the
  /// one the fridge started life holding.
  static MilkKind fromName(String? name) =>
      values.asNameMap()[name] ?? MilkKind.expressed;
}
