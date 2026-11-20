/// Whether to show someone on an iPhone or iPad how to add the app to their
/// Home Screen, and what to tell them.
///
/// iOS never offers to install a web app the way Android's Chrome does. The
/// only way is Share → Add to Home Screen, which most people have never
/// used, and the app needs it more than most: web push only reaches an app
/// opened from the Home Screen (iOS 16.4 and later), so in a Safari tab the
/// feed reminders cannot arrive at all.
///
/// Pure, so it can be tested without a browser. `browser_env.dart` supplies
/// the inputs from the real page.
library;

/// Which iOS browser the page is open in, as far as the steps differ.
enum IosBrowser {
  /// Safari: the Share button is in the toolbar.
  safari,

  /// Chrome, Edge or Firefox for iOS. Since iOS 16.4 they can add to the
  /// Home Screen too, from their own Share menu.
  otherBrowser,

  /// A browser inside another app — Gmail, Instagram, Facebook, Google.
  /// These have no Add to Home Screen at all; the page has to be opened in
  /// Safari first.
  inApp,
}

class IosInstallHint {
  const IosInstallHint({
    required this.browser,
    required this.notificationsSupported,
  });

  final IosBrowser browser;

  /// False on iOS before 16.4, where even a Home Screen web app gets no
  /// notifications. Adding it is still worth it — full screen, its own icon,
  /// opens offline — but the reminders should not be promised.
  final bool notificationsSupported;

  @override
  bool operator ==(Object other) =>
      other is IosInstallHint &&
      other.browser == browser &&
      other.notificationsSupported == notificationsSupported;

  @override
  int get hashCode => Object.hash(browser, notificationsSupported);

  @override
  String toString() => 'IosInstallHint($browser, $notificationsSupported)';
}

/// The hint for this page, or null when there is nothing to suggest: not
/// iOS, or already opened from the Home Screen.
///
/// [standalone] is whether the page is running as an installed app
/// (`navigator.standalone`, or the `display-mode: standalone` media query).
/// [maxTouchPoints] tells an iPad apart from a Mac: iPadOS 13 and later
/// asks for desktop sites and so reports itself as a Mac, but no Mac has a
/// touch screen.
IosInstallHint? iosInstallHint({
  required String userAgent,
  required int maxTouchPoints,
  required bool standalone,
}) {
  if (standalone) return null;

  final iPhoneOrOldIPad = RegExp(r'iPhone|iPad|iPod').hasMatch(userAgent);
  final desktopIPad = userAgent.contains('Macintosh') && maxTouchPoints > 1;
  if (!iPhoneOrOldIPad && !desktopIPad) return null;

  return IosInstallHint(
    browser: _browser(userAgent),
    notificationsSupported: _notificationsSupported(userAgent),
  );
}

IosBrowser _browser(String ua) {
  // In-app browsers first: they carry Safari's tokens as well.
  if (RegExp(
    r'FBAN|FBAV|Instagram|GSA/|LinkedInApp|Line/|Twitter|Snapchat',
  ).hasMatch(ua)) {
    return IosBrowser.inApp;
  }
  if (RegExp(r'CriOS|EdgiOS|FxiOS|OPiOS').hasMatch(ua)) {
    return IosBrowser.otherBrowser;
  }
  // Every iOS browser is WebKit and says "Safari"; Safari itself also says
  // "Version/". A web view inside some other app usually has neither.
  if (ua.contains('Safari/') && ua.contains('Version/')) {
    return IosBrowser.safari;
  }
  return IosBrowser.inApp;
}

/// Web push for Home Screen apps arrived in iOS 16.4.
///
/// The iPhone's user agent says "OS 16_4"; a desktop-mode iPad's does not
/// give its iOS version at all, but desktop mode is iPadOS 13 and later and
/// any iPad still in use is well past 16.4 — so an unknown version is
/// treated as supported rather than warning everyone.
bool _notificationsSupported(String ua) {
  final match = RegExp(r'OS (\d+)_(\d+)').firstMatch(ua);
  if (match == null) return true;
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return major > 16 || (major == 16 && minor >= 4);
}
