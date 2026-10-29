import 'package:flutter/material.dart';

import '../../data/models/medication_event.dart';

/// Display helpers for doses of medicine (#37).
abstract final class MedicationFormat {
  static const label = 'Medicine';
  static const icon = Icons.medication_outlined;

  /// "2.5 ml", or null when no dose was written down.
  static String? dose(MedicationEvent e) {
    final d = e.dose;
    final u = e.unit;
    if (d == null) return null;
    return u == null ? _number(d) : u.amount(d);
  }

  /// "Tylenol 2.5 ml".
  static String nameAndDose(MedicationEvent e) => [e.name, ?dose(e)].join(' ');

  /// Who logged it: "you" for this account's own doses, otherwise the name
  /// they had when they logged it. Null when there is neither.
  static String? givenBy(MedicationEvent e, String? myUid) {
    if (e.createdBy != null && e.createdBy == myUid) return 'you';
    final name = e.byName?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  /// "2.5 ml · by you · fussy": everything but the name.
  static String details(MedicationEvent e, String? myUid) {
    final by = givenBy(e, myUid);
    return [
      ?dose(e),
      if (by != null) 'by $by',
      if (e.notes != null && e.notes!.trim().isNotEmpty) e.notes!.trim(),
    ].join(' · ');
  }

  static String _number(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

/// "Tylenol ×2 · Ibuprofen": how many doses of each, most given first. The
/// count is left off a medicine given once.
String dosesByMedicine(List<MedicationEvent> doses) {
  final counts = <String, int>{};
  for (final d in doses) {
    counts[d.name.trim()] = (counts[d.name.trim()] ?? 0) + 1;
  }
  final names = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [
    for (final n in names) counts[n]! > 1 ? '$n ×${counts[n]}' : n,
  ].join(' · ');
}
