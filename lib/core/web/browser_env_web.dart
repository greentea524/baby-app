import 'dart:js_interop';

import 'browser_env.dart';

@JS('navigator.userAgent')
external JSString get _userAgent;

@JS('navigator.maxTouchPoints')
external JSNumber? get _maxTouchPoints;

/// Safari's own flag for a page opened from the Home Screen. Other browsers
/// do not define it.
@JS('navigator.standalone')
external JSBoolean? get _iosStandalone;

@JS('matchMedia')
external _MediaQueryList _matchMedia(JSString query);

extension type _MediaQueryList(JSObject _) implements JSObject {
  external bool get matches;
}

@JS('open')
external JSAny? _open(JSString url, JSString target);

BrowserEnv? readBrowserEnv() {
  try {
    final standalone =
        (_iosStandalone?.toDart ?? false) ||
        _matchMedia('(display-mode: standalone)'.toJS).matches;
    return BrowserEnv(
      userAgent: _userAgent.toDart,
      maxTouchPoints: _maxTouchPoints?.toDartInt ?? 0,
      standalone: standalone,
    );
  } catch (_) {
    // Any of these missing means a browser too unusual to advise about,
    // and no advice is better than a crash.
    return null;
  }
}

/// Opens [url] in a new tab.
///
/// A new tab, not this one: in an app opened from the iPhone Home Screen
/// there is no back button, so a page that replaced the app would leave
/// nobody a way back to it. iOS shows a new tab as a sheet over the app
/// with a Done button.
void openInNewTab(String url) {
  try {
    _open(url.toJS, '_blank'.toJS);
  } catch (_) {
    // Blocked by the browser: nothing more to do from here.
  }
}
