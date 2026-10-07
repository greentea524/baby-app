{{flutter_js}}
{{flutter_build_config}}

// Customised so the loading screen in index.html survives until the app is
// actually on screen.
//
// The stock bootstrap is a bare `_flutter.loader.load(...)`, which leaves the
// page blank from the moment the PWA opens until Flutter paints — several
// seconds on a phone, since that window covers downloading main.dart.js,
// fetching and compiling CanvasKit, and booting the engine.
// Armed here rather than anywhere inside the load, because the ways a boot
// fails are mostly ways it never returns: a CanvasKit fetch that hangs leaves
// initializeEngine() pending forever, and any timer sitting behind that await
// is never set. A loading screen with nothing coming would otherwise sit
// there swallowing every tap.
setTimeout(dismissLoadingScreen, 25000);

// No serviceWorkerSettings: Flutter's own worker unregisters itself on
// 3.44, and registering it at the root would replace ours. See
// registerAppServiceWorker below.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    // The same two steps the default runner performs.
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();

    // Deliberately not dismissing here. runApp resolves once Dart's main()
    // has been *invoked*, and main() then awaits Firebase and the stored
    // preferences before rendering — so this point is still a blank canvas.
    // main() calls dismissLoadingScreen() itself after the first frame; see
    // lib/core/web/loading_screen.dart.
  }
});

// Called from Dart once the first frame has painted. Global on purpose —
// that is how the Dart side reaches it.
function dismissLoadingScreen() {
  const screen = document.getElementById('app-loading');
  if (!screen) return;

  // The html background carries the loading colour so the status bar and
  // overscroll match it. Hand that back to the app.
  document.documentElement.style.background = '';
  screen.classList.add('app-loading--done');

  // Removed when the fade ends, or on a timer if that event never arrives —
  // transitionend does not fire when the transition is suppressed, and a
  // loading screen stuck at opacity 0 would still swallow every tap.
  let removed = false;
  const remove = function () {
    if (removed) return;
    removed = true;
    screen.remove();
  };
  screen.addEventListener('transitionend', remove, { once: true });
  setTimeout(remove, 600);

  // The app is up, so whatever it loaded from the CDN to get here is known.
  warmOfflineCache();
  // Fonts for characters first drawn a little later — an emoji, a name in
  // another script — load after the first frame. Once more catches them.
  setTimeout(warmOfflineCache, 15000);
}

// --- Opening with no connection (#34) --------------------------------------
//
// web/app_sw.js keeps a copy of this build and of what it loads from the
// CDN, so the app opens with no signal. These are the page's half: register
// it, say when a new version is ready, and switch to it when asked.

// The warm-up below reads the browser's list of fetched resources, which
// holds 250 by default; Firestore's own traffic can fill that before the
// second warm-up runs, and the CDN files would have fallen off the front.
if (performance.setResourceTimingBufferSize) {
  performance.setResourceTimingBufferSize(1000);
}

// Set once a newer version has been downloaded and is waiting. Read by Dart
// (lib/core/web/app_update_web.dart), which also listens for the event.
window.appUpdateWaiting = false;

// Only a reload the person asked for — not the worker taking over on the
// very first visit, which changes the controller too.
let appUpdateRequested = false;

(function registerAppServiceWorker() {
  // Registered under `flutter run` too, where it is harmless: the worker
  // there is the unstamped template, which caches nothing.
  if (!('serviceWorker' in navigator)) return;

  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (!appUpdateRequested) return;
    appUpdateRequested = false;
    location.reload();
  });

  navigator.serviceWorker
    .register('app_sw.js', { scope: './', updateViaCache: 'none' })
    .then(function (registration) {
      const announce = function () {
        window.appUpdateWaiting = true;
        window.dispatchEvent(new Event('app-update-ready'));
      };
      // Only when something is already in charge: the first install is not
      // an update, it is the first version.
      if (registration.waiting && navigator.serviceWorker.controller) announce();
      registration.addEventListener('updatefound', function () {
        const incoming = registration.installing;
        if (!incoming) return;
        incoming.addEventListener('statechange', function () {
          if (incoming.state === 'installed' && navigator.serviceWorker.controller) {
            announce();
          }
        });
      });
      // A PWA left open for days is never navigated, which is when browsers
      // look for a new worker by themselves. Coming back to it is the next
      // best moment.
      document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible') {
          registration.update().catch(function () {});
        }
      });
    })
    .catch(function (error) {
      console.warn('Offline support is unavailable:', error);
    });
})();

// Switches to the waiting version: called from Dart when Reload is tapped.
function applyAppUpdate() {
  if (!('serviceWorker' in navigator)) return location.reload();
  navigator.serviceWorker.getRegistration().then(function (registration) {
    if (registration && registration.waiting) {
      appUpdateRequested = true;
      registration.waiting.postMessage({ type: 'skip-waiting' });
    } else {
      location.reload();
    }
  });
}

// Hands the worker the list of everything this page has fetched, from which
// it keeps the CDN files. On the first visit those were loaded before the
// worker was running, so this is the only way it learns of them.
//
// Waits for the worker to be active rather than in charge of the page: on a
// first visit it is still installing when the app first paints.
function warmOfflineCache() {
  if (!('serviceWorker' in navigator)) return;
  navigator.serviceWorker.ready.then(function (registration) {
    const urls = performance
      .getEntriesByType('resource')
      .map(function (entry) { return entry.name; });
    if (registration.active) {
      registration.active.postMessage({ type: 'warm', urls: urls });
    }
  });
}
