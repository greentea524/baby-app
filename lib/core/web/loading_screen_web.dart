import 'dart:js_interop';

@JS('dismissLoadingScreen')
external void _dismissLoadingScreen();

/// Fades out and removes the loading screen from `web/index.html`.
void dismissLoadingScreen() {
  try {
    _dismissLoadingScreen();
  } catch (_) {
    // The function is defined by our own web/flutter_bootstrap.js, so it is
    // there in any build of this app — but not necessarily when the compiled
    // output is loaded by some other host page. Failing to remove a loading
    // screen that was never added is not worth taking the app down for.
  }
}
