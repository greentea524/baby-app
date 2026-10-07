/// A new version of the web app, downloaded and waiting (#34).
///
/// `web/app_sw.js` keeps the app's files so it opens with no connection,
/// which means a new deploy is not picked up by simply loading the page: it
/// downloads in the background and waits. These are the calls that find out
/// it is there and switch to it — see `web/flutter_bootstrap.js`.
///
/// No-ops off the web, where the app updates through its store.
library;

export 'app_update_stub.dart'
    if (dart.library.js_interop) 'app_update_web.dart';
