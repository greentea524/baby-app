/// Takes down the HTML loading screen that covers the app's boot.
///
/// The screen lives in `web/index.html` and is removed by
/// `web/flutter_bootstrap.js`; this is the call that triggers it. It has to
/// come from Dart rather than from the bootstrap's own `runApp()` promise,
/// because that promise resolves as soon as `main()` is invoked — while
/// `main()` is still awaiting Firebase and stored preferences, with nothing
/// on screen.
///
/// A no-op off the web, where there is no such screen.
library;

export 'loading_screen_stub.dart'
    if (dart.library.js_interop) 'loading_screen_web.dart';
