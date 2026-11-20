import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/web/browser_env.dart';

/// The privacy policy, a static page beside the app: `web/privacy.html`.
///
/// Static rather than a screen in the app, because it has to be readable by
/// people who have not signed in — and by Google, whose sign-in consent
/// screen links to it — without loading the app at all.
const privacyPolicyPath = '/privacy.html';

void openPrivacyPolicy() => openInNewTab(privacyPolicyPath);

/// Only on the web for now: that is where the page is served, and the app
/// has no way to open a link off the web until it carries url_launcher.
bool get privacyPolicyAvailable => kIsWeb;

/// A small "Privacy policy" link, for under the sign-in buttons.
class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({super.key});

  @override
  Widget build(BuildContext context) {
    if (!privacyPolicyAvailable) return const SizedBox.shrink();
    return TextButton(
      onPressed: openPrivacyPolicy,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        textStyle: Theme.of(context).textTheme.bodySmall,
      ),
      child: const Text('Privacy policy'),
    );
  }
}
