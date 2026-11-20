/// What the page can tell about the browser it is in, and opening another
/// page beside the app.
///
/// Off the web there is no browser: [readBrowserEnv] returns null and
/// [openInNewTab] does nothing.
library;

export 'browser_env_stub.dart'
    if (dart.library.js_interop) 'browser_env_web.dart';

/// The browser facts `install_hint.dart` decides from.
class BrowserEnv {
  const BrowserEnv({
    required this.userAgent,
    required this.maxTouchPoints,
    required this.standalone,
  });

  final String userAgent;
  final int maxTouchPoints;

  /// Opened from the Home Screen (or installed, on other platforms) rather
  /// than in a browser tab.
  final bool standalone;
}
