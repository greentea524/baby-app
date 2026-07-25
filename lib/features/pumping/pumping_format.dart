import 'package:flutter/material.dart';

import '../../data/models/pumping_event.dart';
import '../feeding/feeding_format.dart';

/// Display helpers for pump sessions (KAN-145).
abstract final class PumpingFormat {
  static const label = 'Pumping';
  static const icon = Icons.opacity;

  /// e.g. "18 min · Both · 120 ml".
  static String details(PumpingEvent e) {
    final parts = <String>[
      if (e.durationMinutes != null) '${e.durationMinutes} min',
      if (e.side != null) FeedingFormat.sideLabel(e.side!),
      if (e.amountMl != null) '${_trim(e.amountMl!)} ml',
      if (e.notes != null && e.notes!.trim().isNotEmpty) e.notes!.trim(),
    ];
    return parts.join(' · ');
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
