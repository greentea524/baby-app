import '../../data/models/medication_event.dart';

/// The waits offered between doses, in hours. A short list rather than a
/// free field: these are what labels and doctors say, and a typed "6" next
/// to a unit to get wrong is how a wait becomes six days.
const List<int> waitChoices = [4, 6, 8, 12, 24];

/// One medicine as one key, whatever the case or spacing it was typed in.
String medicineKey(String name) => name.trim().toLowerCase();

/// The latest dose of [name] in [doses], leaving out [excludeId] — the dose
/// being edited, which is not its own previous dose.
MedicationEvent? lastDoseOf(
  List<MedicationEvent> doses,
  String name, {
  String? excludeId,
}) {
  final key = medicineKey(name);
  MedicationEvent? last;
  for (final d in doses) {
    if (d.id == excludeId || medicineKey(d.name) != key) continue;
    if (last == null || d.time.isAfter(last.time)) last = d;
  }
  return last;
}

/// When the next dose after [dose] may be given, by the wait set on it, or
/// null when it has none.
DateTime? nextAllowedAfter(MedicationEvent dose) {
  final hours = dose.waitHours;
  if (hours == null || hours <= 0) return null;
  return dose.time.add(Duration(hours: hours));
}

/// How many doses of [name] in the 24 hours up to [now] — the window labels
/// give their daily limits in, rather than the calendar day.
int dosesInLast24h(List<MedicationEvent> doses, String name, DateTime now) {
  final key = medicineKey(name);
  final from = now.subtract(const Duration(hours: 24));
  return doses
      .where(
        (d) =>
            medicineKey(d.name) == key &&
            d.time.isAfter(from) &&
            !d.time.isAfter(now),
      )
      .length;
}

/// A medicine still inside its wait: given at [last], allowed again at
/// [allowedAt].
typedef MedWait = ({MedicationEvent last, DateTime allowedAt});

/// Every medicine whose latest dose is still inside its wait at [now],
/// soonest allowed first.
List<MedWait> activeWaits(List<MedicationEvent> doses, DateTime now) {
  final latest = <String, MedicationEvent>{};
  for (final d in doses) {
    final key = medicineKey(d.name);
    final seen = latest[key];
    if (seen == null || d.time.isAfter(seen.time)) latest[key] = d;
  }
  final waits = <MedWait>[
    for (final d in latest.values)
      if (nextAllowedAfter(d) case final at? when at.isAfter(now))
        (last: d, allowedAt: at),
  ]..sort((a, b) => a.allowedAt.compareTo(b.allowedAt));
  return waits;
}

/// How much of [wait] is still to run at [now], 1 just after the dose to 0
/// when the next is allowed: for the countdown track under its chip.
double waitRemaining(MedWait wait, DateTime now) {
  final whole = wait.allowedAt.difference(wait.last.time).inSeconds;
  if (whole <= 0) return 0;
  return (wait.allowedAt.difference(now).inSeconds / whole).clamp(0.0, 1.0);
}

/// Whether a dose of [name] at [at] comes before the wait set on the one
/// before it is over — what the sheet asks about before saving.
MedicationEvent? tooSoonAfter(
  List<MedicationEvent> doses,
  String name,
  DateTime at, {
  String? excludeId,
}) {
  final before = doses.where((d) => !d.time.isAfter(at)).toList();
  final last = lastDoseOf(before, name, excludeId: excludeId);
  if (last == null) return null;
  final allowed = nextAllowedAfter(last);
  return allowed != null && at.isBefore(allowed) ? last : null;
}
