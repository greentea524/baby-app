import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../core/web/browser_env.dart';
import '../../core/web/install_hint.dart';

/// The Add to Home Screen hint for this device, or null when there is
/// none to give — anywhere but an iPhone or iPad browser tab.
///
/// Read once: whether the page was opened from the Home Screen does not
/// change while it is open. Overridden in tests.
final iosInstallHintProvider = Provider<IosInstallHint?>((ref) {
  final env = readBrowserEnv();
  if (env == null) return null;
  return iosInstallHint(
    userAgent: env.userAgent,
    maxTouchPoints: env.maxTouchPoints,
    standalone: env.standalone,
  );
});

const _dismissedKey = 'install_hint_dismissed';

/// Whether Home's banner has been put away on this device.
///
/// Per device, in local storage, because "add it to *this* phone's Home
/// Screen" is about this phone. Settings keeps a way back to the guide.
final installBannerDismissedProvider =
    NotifierProvider<InstallBannerDismissed, bool>(InstallBannerDismissed.new);

class InstallBannerDismissed extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(_dismissedKey) ?? false;

  Future<void> dismiss() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_dismissedKey, true);
  }
}

void openInstallGuide(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const InstallGuideScreen()));

/// The prompt to add the app to the Home Screen, for an iPhone or iPad
/// browser tab. Nothing anywhere else.
///
/// On the login screen it cannot be dismissed, and says to do it *before*
/// signing in: an app added to the Home Screen keeps its own storage, apart
/// from Safari's, so signing in here first only means signing in twice.
/// On Home it can be put away, for whoever prefers the tab.
class InstallBanner extends ConsumerWidget {
  const InstallBanner({super.key, this.beforeSignIn = false});

  final bool beforeSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = ref.watch(iosInstallHintProvider);
    if (hint == null) return const SizedBox.shrink();
    if (!beforeSignIn && ref.watch(installBannerDismissedProvider)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final why = hint.notificationsSupported
        ? 'It opens full screen, works offline, and can send feed reminders '
              '— which it cannot do from a browser tab.'
        : 'It opens full screen and works offline.';

    return Card(
      margin: beforeSignIn
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.add_to_home_screen,
                  color: scheme.onTertiaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    beforeSignIn
                        ? 'Add Baby App to your Home Screen first, then sign '
                              'in from there. $why'
                        : 'Add Baby App to your Home Screen. $why',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!beforeSignIn)
                  TextButton(
                    onPressed: () => ref
                        .read(installBannerDismissedProvider.notifier)
                        .dismiss(),
                    child: const Text('Not now'),
                  ),
                TextButton(
                  onPressed: () => openInstallGuide(context),
                  child: const Text('Show me how'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Step by step, with the icons the person will be looking for.
///
/// Written for whichever browser they are in: Safari and the others put
/// Share in different places, and an in-app browser (opened from a link in
/// Gmail or Instagram) has no Add to Home Screen at all.
class InstallGuideScreen extends ConsumerWidget {
  const InstallGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint =
        ref.watch(iosInstallHintProvider) ??
        // Reached from somewhere that is not an iOS tab — Settings on an
        // app already added, say. Safari's steps are the useful default.
        const IosInstallHint(
          browser: IosBrowser.safari,
          notificationsSupported: true,
        );
    final theme = Theme.of(context);

    final steps = switch (hint.browser) {
      IosBrowser.inApp => const [
        _Step(
          icon: Icons.open_in_new,
          text:
              'This page is open inside another app, which cannot add it to '
              'your Home Screen. Tap that app\'s menu (often ••• or the '
              'compass) and choose Open in Safari.',
        ),
        _Step(
          icon: Icons.ios_share,
          text: 'In Safari, tap the Share button in the toolbar.',
        ),
        _addStep,
        _confirmStep,
        _openStep,
      ],
      IosBrowser.otherBrowser => const [
        _Step(
          icon: Icons.ios_share,
          text:
              'Tap the Share button — in Chrome and Edge it is at the top '
              'right, next to the address. In Firefox, open the menu first.',
        ),
        _addStep,
        _confirmStep,
        _openStep,
      ],
      IosBrowser.safari => const [
        _Step(
          icon: Icons.ios_share,
          text:
              'Tap the Share button: the square with an arrow pointing up. '
              'On iPhone it is in the bar at the bottom (tap ••• first if '
              'you only see the address); on iPad, at the top.',
        ),
        _addStep,
        _confirmStep,
        _openStep,
      ],
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Add to Home Screen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Baby App installs from the browser — there is nothing to '
            'download from the App Store.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          for (final (i, step) in steps.indexed) step.build(context, i + 1),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          Text('Good to know', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _Note(
            hint.notificationsSupported
                ? 'Feed reminders only work in the app opened from the Home '
                      'Screen. Turn them on there, in Settings.'
                : 'This iPhone is on a version of iOS before 16.4, which '
                      'cannot send notifications from a web app. Update iOS '
                      'to get feed reminders.',
          ),
          const _Note(
            'The Home Screen app is kept separate from Safari, so you sign '
            'in once more there. Everything you have logged is already '
            'saved to your account and will be waiting.',
          ),
          const _Note(
            'If you don\'t see Add to Home Screen, scroll down the Share '
            'menu, or tap Edit Actions to add it.',
          ),
        ],
      ),
    );
  }
}

const _addStep = _Step(
  icon: Icons.add_box_outlined,
  text: 'Scroll down the list and tap Add to Home Screen.',
);

const _confirmStep = _Step(
  icon: Icons.check,
  text:
      'Make sure Open as Web App is on, if you see it, then tap Add in '
      'the top corner.',
);

const _openStep = _Step(
  icon: Icons.child_care,
  text:
      'Close the browser and open Baby App from its new icon on your Home '
      'Screen.',
);

class _Step {
  const _Step({required this.icon, required this.text});

  final IconData icon;
  final String text;

  Widget build(BuildContext context, int number) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: Text('$number', style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
          const SizedBox(width: 12),
          // The icon they will be hunting for on screen, beside the words.
          Icon(icon, color: scheme.primary),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
