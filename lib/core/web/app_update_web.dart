import 'dart:js_interop';

@JS('appUpdateWaiting')
external JSBoolean? get _waiting;

@JS('addEventListener')
external void _addEventListener(JSString type, JSFunction listener);

@JS('applyAppUpdate')
external void _applyAppUpdate();

/// Calls [ready] once a new version is waiting: straight away if one
/// already is, otherwise when it finishes downloading.
void onAppUpdateReady(void Function() ready) {
  try {
    if (_waiting?.toDart ?? false) {
      ready();
      return;
    }
    _addEventListener('app-update-ready'.toJS, ready.toJS);
  } catch (_) {
    // Defined by our own web/flutter_bootstrap.js, so always there in a
    // build of this app; another host page may not have it, and missing an
    // update prompt is no reason to fail.
  }
}

/// Switches to the waiting version, reloading the page into it.
void applyAppUpdate() {
  try {
    _applyAppUpdate();
  } catch (_) {
    // As above.
  }
}
