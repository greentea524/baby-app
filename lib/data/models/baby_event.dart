/// Something that happened to a baby and got written down.
///
/// Exists so [EventRepository] can store and edit any of them without knowing
/// which it is holding. Deliberately the smallest thing that makes that
/// possible — an id to address the document by, and the map to put in it.
/// Everything else about a feed, a diaper or a measurement is that model's
/// own business and stays there.
///
/// `implements` rather than `extends`, so the models keep their own
/// constructors and stay plain data.
abstract interface class BabyEvent {
  /// Empty for an event that has not been stored yet; the document id
  /// afterwards.
  String get id;

  Map<String, dynamic> toMap();
}
