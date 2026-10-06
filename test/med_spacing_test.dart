import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/medication_event.dart';
import 'package:baby_app/features/medication/med_spacing.dart';

/// The wait between doses (#37, phase 2): set per dose by the caregiver,
/// read from a medicine's latest dose.
void main() {
  final now = DateTime(2026, 10, 6, 14);

  MedicationEvent dose(
    String name, {
    required double hoursAgo,
    int? wait,
    String? id,
  }) => MedicationEvent(
    id: id ?? '$name-$hoursAgo',
    time: now.subtract(Duration(minutes: (hoursAgo * 60).round())),
    name: name,
    waitHours: wait,
  );

  test('a medicine is one, whatever its case or spacing', () {
    expect(medicineKey(' Tylenol '), medicineKey('tylenol'));
  });

  test('the latest dose of a medicine sets its wait', () {
    final doses = [
      dose('Tylenol', hoursAgo: 9, wait: 4),
      dose('tylenol', hoursAgo: 2, wait: 6),
      dose('Ibuprofen', hoursAgo: 1, wait: 8),
    ];
    expect(lastDoseOf(doses, 'TYLENOL')!.waitHours, 6);
    expect(
      nextAllowedAfter(lastDoseOf(doses, 'Tylenol')!),
      now.add(const Duration(hours: 4)),
    );
  });

  test('only medicines still inside their wait are waiting, soonest first', () {
    final waits = activeWaits([
      dose('Tylenol', hoursAgo: 2, wait: 6), // allowed in 4 h
      dose('Ibuprofen', hoursAgo: 7, wait: 8), // allowed in 1 h
      dose('Gripe water', hoursAgo: 1), // no wait
      dose('Amoxicillin', hoursAgo: 13, wait: 12), // allowed already
    ], now);
    expect(waits.map((w) => w.last.name), ['Ibuprofen', 'Tylenol']);
    expect(waitRemaining(waits.first, now), closeTo(1 / 8, 0.01));
  });

  test('a dose inside the wait is too soon, one after it is not', () {
    final doses = [dose('Tylenol', hoursAgo: 2, wait: 6)];
    expect(tooSoonAfter(doses, 'Tylenol', now), isNotNull);
    expect(
      tooSoonAfter(doses, 'Tylenol', now.add(const Duration(hours: 4))),
      isNull,
    );
    // Another medicine is not held up by it.
    expect(tooSoonAfter(doses, 'Ibuprofen', now), isNull);
  });

  test('doses are counted over the last 24 hours, not the day', () {
    final doses = [
      dose('Tylenol', hoursAgo: 1),
      dose('Tylenol', hoursAgo: 7),
      dose('Tylenol', hoursAgo: 23),
      dose('Tylenol', hoursAgo: 25),
      dose('Ibuprofen', hoursAgo: 2),
    ];
    expect(dosesInLast24h(doses, 'tylenol', now), 3);
  });
}
