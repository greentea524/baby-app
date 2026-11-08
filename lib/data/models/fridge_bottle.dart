import 'package:cloud_firestore/cloud_firestore.dart';

import 'baby_event.dart';
import 'milk_kind.dart';

export 'milk_kind.dart';

/// What the milk is kept in: a feeding bottle, or a storage container that
/// is poured from. Only how it is drawn and named; it keeps, fills and is
/// fed from the same way.
///
/// Stored by [name]; the rules accept exactly these. A missing or unknown
/// one is a bottle, which is what every one was before containers.
enum Vessel {
  bottle('Bottle'),
  container('Container');

  const Vessel(this.label);

  final String label;

  static Vessel fromName(String? name) =>
      values.asNameMap()[name] ?? Vessel.bottle;
}

/// One bottle standing in the fridge. Stored at
/// `babies/{babyId}/bottles/{id}`.
///
/// Deliberately not derived from a pump session. A session is something that
/// happened and stays in the record forever; a bottle is something that is
/// *there now* and stops being there when it is poured. One session can become
/// two bottles, two sessions can be combined into one, milk fed straight from
/// the pump never reaches the fridge at all — and a formula bottle was never
/// pumped by anybody. So the fridge is its own list, added to and removed from
/// by hand.
class FridgeBottle implements BabyEvent {
  const FridgeBottle({
    required this.id,
    required this.filledAt,
    required this.amountMl,
    this.kind = MilkKind.expressed,
    this.notes,
    this.pumpId,
    this.parts,
    this.placeAt,
    this.vessel = Vessel.bottle,
  });

  @override
  final String id;

  /// When this became a bottle: expressed, or mixed. Not when it was written
  /// down — it is what decides how old the milk is, which is the whole
  /// question the shelf answers.
  ///
  /// One field for both kinds rather than two half-used ones. What it means
  /// is [MilkKind.filledLabel]'s job to say.
  final DateTime filledAt;

  final double amountMl;

  final MilkKind kind;

  final String? notes;

  /// The pump session this milk came from, when it is known: chosen when the
  /// bottle was added, or set when it went in the fridge from the pump sheet.
  /// Null for formula and whole milk, for a bottle whose session nobody
  /// said, and for every bottle from before it was kept.
  final String? pumpId;

  /// What a bottle combined from others holds: how much of each age, as it
  /// was when they were poured together. Null for a bottle of one age, which
  /// is almost every bottle; see [layers] for reading it.
  final List<MilkPart>? parts;

  /// What it is kept in.
  final Vessel vessel;

  /// The time its place on the shelf is ordered by, when that is not
  /// [filledAt]: a bottle that older milk was poured into keeps the place it
  /// had, rather than jumping along the shelf to where its new age would
  /// put it. Null for almost every bottle; see [placedBy].
  final DateTime? placeAt;

  /// What the shelf orders it by: where it stood before anything was poured
  /// into it, or else its age.
  DateTime get placedBy => placeAt ?? filledAt;

  /// The most ages one bottle tells apart. Past it the two closest are taken
  /// as one, at the older time: four shades are as many as read apart at a
  /// glance, and erring old is the safe way with milk.
  static const maxParts = 4;

  /// What is in the bottle, oldest first, adding up to [amountMl].
  ///
  /// The milk is mixed, so what is poured out takes from each age alike:
  /// the stored parts are shares, scaled here to whatever is left. One part,
  /// at [filledAt], for a bottle of one age.
  List<MilkPart> get layers {
    final p = parts;
    final total = p?.fold<double>(0, (acc, x) => acc + x.amountMl) ?? 0;
    if (p == null || p.length < 2 || total <= 0) {
      return [MilkPart(filledAt: filledAt, amountMl: amountMl)];
    }
    return [
      for (final x in p)
        MilkPart(filledAt: x.filledAt, amountMl: x.amountMl * amountMl / total),
    ];
  }

  /// Whether it holds milk of more than one age.
  bool get isMixed => layers.length > 1;

  FridgeBottle copyWith({
    DateTime? filledAt,
    double? amountMl,
    MilkKind? kind,
    String? notes,
  }) => FridgeBottle(
    id: id,
    filledAt: filledAt ?? this.filledAt,
    amountMl: amountMl ?? this.amountMl,
    kind: kind ?? this.kind,
    notes: notes ?? this.notes,
    pumpId: pumpId,
    parts: parts,
    placeAt: placeAt,
    vessel: vessel,
  );

  /// The same bottle holding one age only, from [filledAt]: what a bottle
  /// whose time is changed by hand becomes.
  FridgeBottle unmixed() => FridgeBottle(
    id: id,
    filledAt: filledAt,
    amountMl: amountMl,
    kind: kind,
    notes: notes,
    pumpId: pumpId,
    vessel: vessel,
  );

  factory FridgeBottle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return FridgeBottle(
      id: doc.id,
      filledAt: (data['filledAt'] as Timestamp).toDate(),
      amountMl: (data['amountMl'] as num).toDouble(),
      kind: MilkKind.fromName(data['kind'] as String?),
      notes: data['notes'] as String?,
      pumpId: data['pumpId'] as String?,
      parts: MilkPart.listFrom(data['parts']),
      placeAt: (data['placeAt'] as Timestamp?)?.toDate(),
      vessel: Vessel.fromName(data['vessel'] as String?),
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'filledAt': Timestamp.fromDate(filledAt),
    'amountMl': amountMl,
    'kind': kind.name,
    'notes': notes,
    'pumpId': pumpId,
    'parts': MilkPart.listToMap(parts),
    'placeAt': placeAt == null ? null : Timestamp.fromDate(placeAt!),
    'vessel': vessel.name,
  };
}

/// Some of the milk in a bottle, and when it was filled.
class MilkPart {
  const MilkPart({required this.filledAt, required this.amountMl});

  final DateTime filledAt;
  final double amountMl;

  /// Null for anything but two or more readable parts: a bottle of one age
  /// is stored without them, and one written wrong is read as one age
  /// rather than not read at all.
  static List<MilkPart>? listFrom(Object? raw) {
    if (raw is! List) return null;
    final parts = <MilkPart>[];
    for (final p in raw) {
      if (p is! Map) return null;
      final at = p['at'];
      final ml = p['ml'];
      if (at is! Timestamp || ml is! num || ml <= 0) return null;
      parts.add(MilkPart(filledAt: at.toDate(), amountMl: ml.toDouble()));
    }
    return parts.length < 2 ? null : parts;
  }

  static List<Map<String, dynamic>>? listToMap(List<MilkPart>? parts) =>
      parts == null || parts.length < 2
      ? null
      : [
          for (final p in parts)
            {'at': Timestamp.fromDate(p.filledAt), 'ml': p.amountMl},
        ];
}
