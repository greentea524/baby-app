import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/diaper_event.dart';
import '../../data/models/diaper_stock_entry.dart';
import '../../data/repositories/repository_providers.dart';

/// How the pile is doing: plenty, running low, or out.
enum StockLevel { ok, low, out }

/// How many diapers are left, worked out rather than stored.
///
/// From the last count, or from nothing before the first pack if there has
/// never been one: what was counted, plus every pack added since, less every
/// change logged since. A change logged for a time before the count is in
/// the count already, so only those from its time on come off.
class DiaperStock {
  const DiaperStock({
    required this.left,
    required this.since,
    required this.used,
    required this.lowAt,
    this.perDay,
  });

  /// How many are left. Below nought only if more were logged than there
  /// were, which is said as none left.
  final int left;

  /// Where the reckoning starts: the last count, or the first pack.
  final DateTime since;

  /// How many changes have come off it since then.
  final int used;

  /// At or below this, it is running low.
  final int lowAt;

  /// Changes a day lately, for how long what is left will last. Null with
  /// none lately to go on.
  final double? perDay;

  StockLevel get level => left <= 0
      ? StockLevel.out
      : left <= lowAt
      ? StockLevel.low
      : StockLevel.ok;

  /// Roughly how many days what is left will last, or null.
  int? get daysLeft {
    final rate = perDay;
    if (rate == null || rate <= 0 || left <= 0) return null;
    return (left / rate).floor();
  }

  /// The stock from [entries] (any order) and the changes logged since
  /// [start] — see [startOf] — or null with nothing recorded.
  static DiaperStock? of(
    List<DiaperStockEntry> entries,
    List<DiaperEvent> diapers, {
    required int lowAt,
    double? perDay,
  }) {
    final start = startOf(entries);
    if (start == null) return null;
    final counted = lastCount(entries);
    var left = counted?.count ?? 0;
    for (final e in entries) {
      if (e.action == StockAction.added &&
          !e.at.isBefore(start) &&
          e.id != counted?.id) {
        left += e.count;
      }
    }
    final used = diapers.where((d) => !d.time.isBefore(start)).length;
    return DiaperStock(
      left: left - used,
      since: start,
      used: used,
      lowAt: lowAt,
      perDay: perDay,
    );
  }

  /// The latest count, or null if the pile has never been counted.
  static DiaperStockEntry? lastCount(List<DiaperStockEntry> entries) {
    DiaperStockEntry? last;
    for (final e in entries) {
      if (e.action == StockAction.counted &&
          (last == null || e.at.isAfter(last.at))) {
        last = e;
      }
    }
    return last;
  }

  /// Where the reckoning starts: the last count, or else the first pack
  /// added. Null with nothing recorded.
  static DateTime? startOf(List<DiaperStockEntry> entries) {
    if (lastCount(entries) case final c?) return c.at;
    DateTime? first;
    for (final e in entries) {
      if (first == null || e.at.isBefore(first)) first = e.at;
    }
    return first;
  }
}

/// Changes a day over the last three days of [recent], as of [now]; null
/// with none in them.
double? diapersPerDay(List<DiaperEvent> recent, DateTime now) {
  const days = 3;
  final from = now.subtract(const Duration(days: days));
  final n = recent
      .where((d) => d.time.isAfter(from) && !d.time.isAfter(now))
      .length;
  return n == 0 ? null : n / days;
}

const _lowAtKey = 'diaper_stock_low_at';

/// At or below how many the stock is running low. Twenty to start with:
/// a couple of days for a newborn, enough notice to buy more.
final diaperLowAtProvider = NotifierProvider<DiaperLowAtNotifier, int>(
  DiaperLowAtNotifier.new,
);

class DiaperLowAtNotifier extends Notifier<int> {
  static const initial = 20;

  @override
  int build() =>
      ref.read(sharedPreferencesProvider).getInt(_lowAtKey) ?? initial;

  Future<void> set(int value) async {
    state = value < 0 ? 0 : value;
    await ref.read(sharedPreferencesProvider).setInt(_lowAtKey, state);
  }
}

/// The diaper stock now, or null before anything has been recorded.
final diaperStockProvider = Provider<DiaperStock?>((ref) {
  final entries = ref.watch(diaperStockEntriesProvider).value ?? const [];
  final start = DiaperStock.startOf(entries);
  if (start == null) return null;
  final since = ref.watch(diapersSinceProvider(start)).value ?? const [];
  return DiaperStock.of(
    entries,
    since,
    lowAt: ref.watch(diaperLowAtProvider),
    perDay: diapersPerDay(
      ref.watch(recentDiapersProvider).value ?? const [],
      DateTime.now(),
    ),
  );
});
