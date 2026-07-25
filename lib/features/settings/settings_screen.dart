import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../caregivers/caregivers_screen.dart';
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
