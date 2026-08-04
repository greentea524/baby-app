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

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  },
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
}
