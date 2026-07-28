import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/activity_entry.dart';
import '../../data/repositories/repository_providers.dart';
import '../activity/activity_tile.dart';
import '../common/day_stats_chips.dart';
import 'day_stats.dart';
import 'timeline_format.dart';

/// Daily timeline with day navigation, a stats summary, and a chronological
/// list of feeds + diaper changes (KAN-132).
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final feedsAsync = ref.watch(feedingsForDayProvider);
    final diapersAsync = ref.watch(diapersForDayProvider);
    final pumpsAsync = ref.watch(pumpingForDayProvider);
    final baby = ref.watch(currentBabyProvider);

    final loading =
        (!feedsAsync.hasValue && feedsAsync.isLoading) ||
        (!diapersAsync.hasValue && diapersAsync.isLoading) ||
        (!pumpsAsync.hasValue && pumpsAsync.isLoading);

    final feeds = feedsAsync.value ?? const [];
    final diapers = diapersAsync.value ?? const [];
    final pumps = pumpsAsync.value ?? const [];
    final entries = mergeActivities(
      feeds,
      diapers,
      pumps: pumps,
      descending: false,
    );
    final stats = DayStats.from(feeds, diapers, pumps: pumps);

    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: baby == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a baby on the Home tab to see the timeline.'),
              ),
            )
          : Column(
              children: [
                _DayNavBar(day: day),
                if (loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: DayStatsChips(stats: stats),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No events on this day.'),
                            ),
                          )
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) => ActivityTile(
                              entry: entries[i],
                              clockTime: true,
                            ),
                          ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _DayNavBar extends ConsumerWidget {
  const _DayNavBar({required this.day});

  final DateTime day;

  bool get _isToday {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  void _shift(WidgetRef ref, int days) {
    ref.read(selectedDayProvider.notifier).shift(days);
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) {
      ref.read(selectedDayProvider.notifier).setDay(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(ref, -1),
            tooltip: 'Previous day',
          ),
          Expanded(
            child: TextButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(TimelineFormat.dayLabel(day)),
              onPressed: () => _pick(context, ref),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _isToday ? null : () => _shift(ref, 1),
            tooltip: 'Next day',
          ),
        ],
      ),
    );
  }
}
