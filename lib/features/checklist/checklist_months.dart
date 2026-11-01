import 'package:flutter/material.dart';

import '../../data/models/daily_check.dart';
import 'checklist_logic.dart';

/// The last two calendar months of one checklist item, a day to a square:
/// filled for a day it was done, tinted for a day part done, empty for
/// none. Last month and this one, so a month's gaps can be seen whole.
///
/// With more than one item, chips above choose which.
class ChecklistMonths extends StatefulWidget {
  const ChecklistMonths({
    super.key,
    required this.items,
    required this.checks,
    required this.now,
  });

  final List<ChecklistItem> items;

  /// At least the two months shown.
  final List<DailyCheck> checks;
  final DateTime now;

  @override
  State<ChecklistMonths> createState() => _ChecklistMonthsState();
}

class _ChecklistMonthsState extends State<ChecklistMonths> {
  String? _itemId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final item = items.firstWhere(
      (i) => i.id == _itemId,
      orElse: () => items.first,
    );
    final shares = dailyShares(widget.checks, item);
    final today = dayOf(widget.now);
    final thisMonth = DateTime(today.year, today.month);
    final lastMonth = DateTime(today.year, today.month - 1);

    Widget month(DateTime m) =>
        _MonthGrid(month: m, today: today, shares: shares);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Last two months', style: theme.textTheme.titleMedium),
        if (items.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in items)
                ChoiceChip(
                  key: ValueKey('months-${i.id}'),
                  label: Text(i.label),
                  avatar: Icon(checklistIcon(i.icon)),
                  selected: i.id == item.id,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _itemId = i.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // Side by side where there is room for both at a size a finger can
        // read; one above the other on a phone.
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 600
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: month(lastMonth)),
                    const SizedBox(width: 24),
                    Expanded(child: month(thisMonth)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    month(lastMonth),
                    const SizedBox(height: 16),
                    month(thisMonth),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One calendar month: its name, how many of its days so far were done,
/// and a square per day under the weekday initials.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.shares,
  });

  /// The first of the month.
  final DateTime month;
  final DateTime today;
  final Map<DateTime, double> shares;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final local = MaterialLocalizations.of(context);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    // Blank squares before the 1st, so it lands under its weekday.
    final lead = (month.weekday % 7 - local.firstDayOfWeekIndex) % 7;
    final weekdays = [
      for (var i = 0; i < 7; i++)
        local.narrowWeekdays[(local.firstDayOfWeekIndex + i) % 7],
    ];
    final soFar = [
      for (var d = 1; d <= days; d++)
        if (!DateTime(month.year, month.month, d).isAfter(today))
          DateTime(month.year, month.month, d),
    ];
    final done = soFar.where((d) => (shares[d] ?? 0) >= 1).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                local.formatMonthYear(month),
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              '$done of ${soFar.length} ${soFar.length == 1 ? 'day' : 'days'}',
              key: ValueKey('month-count-${month.year}-${month.month}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              _DaySquare(
                day: DateTime(month.year, month.month, d),
                today: today,
                share: shares[DateTime(month.year, month.month, d)] ?? 0,
              ),
          ],
        ),
      ],
    );
  }
}

class _DaySquare extends StatelessWidget {
  const _DaySquare({
    required this.day,
    required this.today,
    required this.share,
  });

  final DateTime day;
  final DateTime today;

  /// 1 for done, a fraction for part done.
  final double share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final future = day.isAfter(today);
    final done = share >= 1;
    final part = !done && share > 0;
    final isToday = day == today;
    final local = MaterialLocalizations.of(context);

    return Semantics(
      label:
          '${local.formatMediumDate(day)}: '
          '${future
              ? 'to come'
              : done
              ? 'done'
              : part
              ? 'part done'
              : 'not done'}',
      excludeSemantics: true,
      child: Container(
        key: ValueKey(
          'day-${day.year}-${day.month}-${day.day}'
          '-${done
              ? 'done'
              : part
              ? 'part'
              : 'none'}',
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: done
              ? scheme.primary
              : part
              ? scheme.primary.withValues(alpha: 0.28)
              : future
              ? null
              : scheme.surfaceContainerHighest,
          border: isToday ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        // Shrinks rather than spilling out of its square at a large text
        // size: seven to a row leaves a phone little more than 40pt each.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${day.day}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: done
                  ? scheme.onPrimary
                  : future
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                  : scheme.onSurface,
              fontWeight: done ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }
}
