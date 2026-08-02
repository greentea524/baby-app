import '../../core/format/unit_system.dart';
import '../../data/models/baby.dart';
import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/growth_measurement.dart';
import '../../data/models/pumping_event.dart';

/// Everything one export covers: the baby, the reporting window, and the
/// records inside it. Built once, then rendered as CSV or PDF (KAN-137).
class ExportData {
  const ExportData({
    required this.baby,
    required this.start,
    required this.end,
    required this.feedings,
    required this.diapers,
    required this.growth,
    // Defaulted rather than required: pumping is opt-in, and every existing
    // caller predates it.
    this.pumps = const [],
    this.units = UnitSystem.us,
  });

  final Baby baby;

  /// Inclusive start, exclusive end.
  final DateTime start;
  final DateTime end;

  final List<FeedingEvent> feedings;
  final List<DiaperEvent> diapers;
  final List<GrowthMeasurement> growth;

  /// Pump sessions in the window. Empty for caregivers who don't pump.
  final List<PumpingEvent> pumps;

  /// Units the report is rendered in; storage stays metric.
  final UnitSystem units;

  bool get isEmpty => feedings.isEmpty && diapers.isEmpty && growth.isEmpty;
}
