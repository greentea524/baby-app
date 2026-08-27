import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/format/unit_system.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/notification_prefs.dart';
import '../../data/repositories/repository_providers.dart';
import '../caregivers/caregivers_screen.dart';
import '../export/export_screen.dart';
import 'delete_account_screen.dart';
import 'delete_baby_screen.dart';
import '../home/home_prefs.dart';
import '../notifications/push_service.dart';
import '../pumping/pumping_format.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';
import '../timeline/timeline_format.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Appearance'),
            subtitle: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                ref.read(themeModeProvider.notifier).setMode(selection.first);
              },
            ),
          ),
          const _AccentPicker(),
          const _HomeActionsPicker(),
          const _HomeLayoutPicker(),
          const _UnitsPicker(),
          const _PumpingActionToggle(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Caregivers'),
            subtitle: const Text('Add and manage who can log'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CaregiversScreen()),
            ),
          ),
          const Divider(),
          const _ReminderSection(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Export data'),
            subtitle: const Text('CSV log or PDF summary report'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ExportScreen()),
            ),
          ),
          const Divider(),
          const _DeleteDataTile(),
          const _DeleteAccountTile(),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Sign out',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
    );
  }
}

/// Theme colour (KAN-180). Swatches rather than names alone — the point of
/// the setting is the colour, so showing it beats describing it.
class _AccentPicker extends ConsumerWidget {
  const _AccentPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(accentProvider);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Colour'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 12,
          children: [
            for (final accent in AppAccent.values)
              Semantics(
                label: accent.label,
                button: true,
                selected: accent == selected,
                child: InkWell(
                  onTap: () =>
                      ref.read(accentProvider.notifier).setAccent(accent),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.seed,
                      border: accent == selected
                          ? Border.all(color: scheme.onSurface, width: 2)
                          : null,
                    ),
                    child: accent == selected
                        ? Icon(Icons.check, size: 18, color: scheme.onPrimary)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where Home's quick-log buttons sit.
///
/// Above the layout picker below, because it is the bigger of the two
/// choices: one moves the thing you came to tap, the other decides whether
/// the rows share a card.
class _HomeActionsPicker extends ConsumerWidget {
  const _HomeActionsPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(homeActionsProvider);
    return ListTile(
      leading: const Icon(Icons.touch_app_outlined),
      title: const Text('Quick actions'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected.description),
          const SizedBox(height: 8),
          SegmentedButton<HomeActions>(
            segments: [
              for (final placement in HomeActions.values)
                ButtonSegment(value: placement, label: Text(placement.label)),
            ],
            selected: {selected},
            onSelectionChanged: (s) =>
                ref.read(homeActionsProvider.notifier).setPlacement(s.first),
          ),
        ],
      ),
    );
  }
}

/// Whether the Home status rows share a card or get their own (KAN-180).
class _HomeLayoutPicker extends ConsumerWidget {
  const _HomeLayoutPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(homeLayoutProvider);
    return ListTile(
      leading: const Icon(Icons.dashboard_outlined),
      title: const Text('Home layout'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected.description),
          const SizedBox(height: 8),
          SegmentedButton<HomeLayout>(
            segments: [
              for (final layout in HomeLayout.values)
                ButtonSegment(value: layout, label: Text(layout.label)),
            ],
            selected: {selected},
            onSelectionChanged: (s) =>
                ref.read(homeLayoutProvider.notifier).setLayout(s.first),
          ),
        ],
      ),
    );
  }
}

/// Units for weights, lengths, and volumes (KAN-182). Storage stays metric;
/// this only changes what is displayed and what the entry fields expect.
class _UnitsPicker extends ConsumerWidget {
  const _UnitsPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(unitSystemProvider);
    return ListTile(
      leading: const Icon(Icons.straighten),
      title: const Text('Units'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected.description),
          const SizedBox(height: 8),
          SegmentedButton<UnitSystem>(
            segments: [
              for (final u in UnitSystem.values)
                ButtonSegment(value: u, label: Text(u.label)),
            ],
            selected: {selected},
            onSelectionChanged: (s) =>
                ref.read(unitSystemProvider.notifier).setUnits(s.first),
          ),
        ],
      ),
    );
  }
}

/// Whether Home offers a "Log pumping" button (KAN-181). On by default, since
/// it is the only way to start a pump entry; the subtitle spells out what
/// turning it off costs.
class _PumpingActionToggle extends ConsumerWidget {
  const _PumpingActionToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(showPumpingActionProvider);
    return SwitchListTile(
      secondary: const Icon(PumpingFormat.icon),
      title: const Text('Pumping button'),
      subtitle: Text(
        enabled
            ? 'Shown on Home under the feed and diaper buttons'
            : 'Hidden — turn on to log pump sessions',
      ),
      value: enabled,
      onChanged: (v) => ref.read(showPumpingActionProvider.notifier).set(v),
    );
  }
}

//// Feed reminder configuration (KAN-133): predicted from recent intervals,
/// a fixed gap, or off.
class _ReminderSection extends ConsumerWidget {
  const _ReminderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    final notifier = ref.read(reminderSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Feed reminder'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<ReminderMode>(
              segments: [
                for (final m in ReminderMode.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {settings.mode},
              onSelectionChanged: (s) => notifier.setMode(s.first),
            ),
          ),
        ),
        if (settings.mode == ReminderMode.fixedInterval)
          ListTile(
            title: const Text('Interval'),
            subtitle: Text(_label(settings.intervalMinutes)),
            trailing: DropdownButton<int>(
              value: settings.intervalMinutes,
              items: const [90, 120, 150, 180, 210, 240, 300, 360]
                  .map(
                    (m) => DropdownMenuItem(value: m, child: Text(_label(m))),
                  )
                  .toList(),
              onChanged: (m) {
                if (m != null) notifier.setIntervalMinutes(m);
              },
            ),
          ),
        if (settings.mode == ReminderMode.fixedInterval) const _RhythmInsight(),
        // Only offered while there is a reminder to give notice of: with the
        // mode off there is no due time and no chip, so this would be a
        // setting with nothing to change.
        if (settings.mode != ReminderMode.off)
          ListTile(
            title: const Text('Heads-up'),
            subtitle: Text(
              settings.headsUpMinutes == 0
                  ? 'Home stays grey until the feed is due, then turns red'
                  : 'Home turns amber '
                        '${_label(settings.headsUpMinutes)} before it is due',
            ),
            trailing: DropdownButton<int>(
              // A stored value outside the list would leave the dropdown with
              // no matching item, which is an assertion rather than a shrug.
              value: headsUpOptions.contains(settings.headsUpMinutes)
                  ? settings.headsUpMinutes
                  : defaultHeadsUpMinutes,
              items: [
                for (final m in headsUpOptions)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m == 0 ? 'Off' : _label(m)),
                  ),
              ],
              onChanged: (m) {
                if (m != null) notifier.setHeadsUpMinutes(m);
              },
            ),
          ),
        // Both of these only govern pushes sent by the reminder Cloud
        // Function. Until that is deployed and the build carries a VAPID key,
        // they are switches with nothing behind them — quiet hours especially,
        // which would promise "no reminders 10 PM – 7 AM" when no reminder can
        // arrive at any hour.
        if (backgroundRemindersAvailable) ...[
          const _PushToggle(),
          const _QuietHoursSection(),
        ],
      ],
    );
  }

  static String _label(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h hr' : '$h hr $m min';
  }
}

/// Quiet hours and the server-side reminder switch (KAN-167). Unlike the
/// device push toggle above, these are stored in Firestore because the
/// scheduled Cloud Function needs to read them when deciding whether to send.
class _QuietHoursSection extends ConsumerWidget {
  const _QuietHoursSection();

  /// Saves, stamping the caregiver's current UTC offset — the server has no
  /// other way to resolve what their local "10 PM" means.
  Future<void> _save(WidgetRef ref, NotificationPrefs prefs) async {
    await ref
        .read(notificationPrefsRepositoryProvider)
        ?.save(
          prefs.copyWith(
            timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
          ),
        );
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    NotificationPrefs prefs, {
    required bool isStart,
  }) async {
    final current = isStart ? prefs.quietStartMinutes : prefs.quietEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await _save(
      ref,
      isStart
          ? prefs.copyWith(quietStartMinutes: minutes)
          : prefs.copyWith(quietEndMinutes: minutes),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs =
        ref.watch(notificationPrefsProvider).value ?? const NotificationPrefs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.bedtime_outlined),
          title: const Text('Quiet hours'),
          subtitle: Text(
            prefs.quietHoursEnabled
                ? 'No reminders ${prefs.quietWindowLabel}'
                : 'Reminders can arrive at any hour',
          ),
          value: prefs.quietHoursEnabled,
          onChanged: (v) => _save(ref, prefs.copyWith(quietHoursEnabled: v)),
        ),
        if (prefs.quietHoursEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _pickTime(context, ref, prefs, isStart: true),
                    child: Text(
                      'From ${NotificationPrefs.formatMinutes(prefs.quietStartMinutes)}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _pickTime(context, ref, prefs, isStart: false),
                    child: Text(
                      'Until ${NotificationPrefs.formatMinutes(prefs.quietEndMinutes)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// What the baby's actual rhythm has been, next to the interval the caregiver
/// picked (KAN-186).
///
/// The interval is theirs to set, but a baby's rhythm stretches as they grow
/// and nobody remembers to revisit a setting — so the app's job is to show
/// when the two have drifted apart, not to quietly re-time the reminder
/// itself.
class _RhythmInsight extends ConsumerWidget {
  const _RhythmInsight();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rhythm = ref.watch(feedRhythmProvider);
    final typical = rhythm.typicalGapMinutes;
    final chosen = ref.watch(reminderSettingsProvider).intervalMinutes;

    // Only worth mentioning once it is a real difference rather than the
    // rhythm wobbling by a few minutes.
    final drifted = typical != null && (typical - chosen).abs() >= 30;

    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reminds you a fixed gap after the last full feed. Snacks and '
            'solids do not reset it, and entries less than '
            '$sameSessionMinutes minutes apart count as one feed.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            typical == null
                ? 'Not enough history yet to compare with your own rhythm.'
                : 'Lately they have fed about every '
                      '${TimelineFormat.interval(typical)}, '
                      'across ${rhythm.samples} recent '
                      '${rhythm.samples == 1 ? 'gap' : 'gaps'}.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (drifted) ...[
            const SizedBox(height: 4),
            Text(
              'That is a way off your ${TimelineFormat.interval(chosen)} '
              'setting — worth adjusting.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opt-in for background push notifications (KAN-156). Registers this
/// device's FCM token; the actual pushes are sent by a scheduled Cloud
/// Function (see functions/ + README).
class _PushToggle extends ConsumerWidget {
  const _PushToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(pushEnabledProvider);
    final uid = ref.watch(authStateProvider).value?.uid;
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: const Text('Background reminders'),
      subtitle: const Text(
        'Get notified when a feed is due, even with the app closed.',
      ),
      value: enabled,
      onChanged: (v) async {
        final ok = await ref.read(pushEnabledProvider.notifier).set(v, uid);
        if (context.mounted && v && !ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notifications were not enabled (permission or setup).',
              ),
            ),
          );
        }
      },
    );
  }
}

/// The way to delete a baby and everything logged under it (#28).
///
/// Beside Export deliberately. They are the two halves of owning the data —
/// take it out, or take it away — and a delete offered on its own is only
/// the half that cannot be undone.
class _DeleteDataTile extends ConsumerWidget {
  const _DeleteDataTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(currentBabyProvider);
    final error = Theme.of(context).colorScheme.error;

    return ListTile(
      leading: Icon(Icons.delete_forever_outlined, color: error),
      title: Text('Delete data', style: TextStyle(color: error)),
      subtitle: Text(
        baby == null
            ? 'No baby selected'
            : 'Permanently remove ${baby.name} and every entry',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: baby == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeleteBabyScreen(baby: baby),
              ),
            ),
    );
  }
}

/// Deleting the account itself (#28, scope B).
///
/// A second row rather than a choice inside the first: deleting one baby and
/// closing the account are different enough that being asked which one you
/// meant, after arriving, is worse than being asked before.
class _DeleteAccountTile extends StatelessWidget {
  const _DeleteAccountTile();

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;

    return ListTile(
      leading: Icon(Icons.person_off_outlined, color: error),
      title: Text('Delete account', style: TextStyle(color: error)),
      subtitle: const Text(
        'Everything you own, your settings, and your sign-in',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DeleteAccountScreen()),
      ),
    );
  }
}
