import '../reminders/feed_prediction.dart';

/// How long a diaper sits before the card starts saying so.
///
/// Two hours to amber, three to red. Not a prediction — unlike feeding there
/// is no rhythm to read, and a nappy left long enough is uncomfortable
/// whatever the baby's habits. Fixed thresholds say the same thing on the
/// first day as on the hundredth.
///
/// Deliberately not a setting yet. One household has asked for one pair of
/// numbers; a preference nobody has asked to change is a screen to maintain
/// and a decision to explain.
const Duration diaperSoonAfter = Duration(hours: 2);
const Duration diaperOverdueAfter = Duration(hours: 3);

/// Where the last change sits against those thresholds.
///
/// Null when nothing has been logged: a card that has never had a change on
/// it is not overdue, it is empty, and colouring it red would be the app
/// inventing a problem out of its own lack of data.
DueState? diaperDueState(DateTime? lastChange, {required DateTime now}) {
  if (lastChange == null) return null;
  // Expressed as a due time so the escalation is literally the same rule the
  // feed clock runs, rather than a second one that resembles it: due at the
  // red threshold, amber for the window before it.
  return feedDueState(
    lastChange.add(diaperOverdueAfter),
    now: now,
    within: diaperOverdueAfter - diaperSoonAfter,
  );
}
