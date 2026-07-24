import '../../data/models/baby.dart';
import '../../data/models/diaper_event.dart';
import '../../data/models/feeding_event.dart';
import '../../data/models/growth_measurement.dart';

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
  });

  final Baby baby;

  /// Inclusive start, exclusive end.
  final DateTime start;
  final DateTime end;

  final List<FeedingEvent> feedings;
  final List<DiaperEvent> diapers;
  final List<GrowthMeasurement> growth;

  bool get isEmpty => feedings.isEmpty && diapers.isEmpty && growth.isEmpty;
}
