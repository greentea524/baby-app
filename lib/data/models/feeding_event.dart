import 'package:cloud_firestore/cloud_firestore.dart';

enum FeedingType { breast, bottle, solids }

enum BreastSide { left, right, both }

/// A feeding event. Stored at `users/{uid}/babies/{babyId}/feedings/{id}`.
/// Full CRUD lands with the Feeding Logging epic (KAN-130); this defines
/// the schema the rest of the app scopes against.
class FeedingEvent {
  const FeedingEvent({
    required this.id,
    required this.type,
    required this.startTime,
    this.durationMinutes,
    this.amountMl,
    this.side,
    this.notes,
    this.isSnack = false,
  });

  final String id;
  final FeedingType type;
  final DateTime startTime;
  final int? durationMinutes;
  final double? amountMl;
  final BreastSide? side;
  final String? notes;

  /// A small top-up rather than a full feed, as marked by the caregiver.
  ///
  /// Snacks don't reset the feeding clock: a 10 ml comfort top-up shouldn't
  /// push the next reminder out by a full interval. Both the predicted and
  /// fixed-interval reminders skip these when working out when the next feed
  /// is due (see `feed_prediction.dart`).
  ///
  /// Deliberately a caregiver's call rather than inferred from volume —
  /// breast feeds carry no volume at all, and a guessed threshold makes the
  /// reminder unpredictable in exactly the case it matters most.
  final bool isSnack;

  /// Whether this event marks a boundary in the feeding rhythm.
  ///
  /// A snack is a top-up rather than a feed's worth of fuel, and solids
  /// supplement milk rather than replace it — neither ends one feeding cycle
  /// and starts the next. The reminders use this to decide when the next feed
  /// is due; the daily stats use it so a 10 ml top-up doesn't halve the
  /// reported average interval.
  bool get drivesFeedClock => !isSnack && type != FeedingType.solids;

  factory FeedingEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return FeedingEvent(
      id: doc.id,
      type: FeedingType.values.byName(data['type'] as String),
      startTime: (data['startTime'] as Timestamp).toDate(),
      durationMinutes: data['durationMinutes'] as int?,
      amountMl: (data['amountMl'] as num?)?.toDouble(),
      side: data['side'] == null
          ? null
          : BreastSide.values.byName(data['side'] as String),
      notes: data['notes'] as String?,
      // Absent on every event logged before snacks existed — those were all
      // full feeds as far as the clock was concerned, so default to false.
      isSnack: data['isSnack'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    'startTime': Timestamp.fromDate(startTime),
    'durationMinutes': durationMinutes,
    'amountMl': amountMl,
    'side': side?.name,
    'notes': notes,
    'isSnack': isSnack,
  };
}
