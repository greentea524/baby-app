import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../data/models/notification_prefs.dart';
import '../../data/repositories/repository_providers.dart';
import '../caregivers/caregivers_screen.dart';
import '../home/home_layout.dart';
import '../export/export_screen.dart';
import '../notifications/push_service.dart';
import '../reminders/reminder_providers.dart';

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
          const _HomeLayoutPicker(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Caregivers'),
            subtitle: const Text('Invite and manage who can log'),
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

/// Feed reminder configuration (KAN-133): predicted from recent intervals,
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
        if (settings.mode == ReminderMode.predictive)
          const Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Text(
              'Uses a rolling average of recent feed intervals.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        const _PushToggle(),
        const _QuietHoursSection(),
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
