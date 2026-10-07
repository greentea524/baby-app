// The app's own service worker: lets the PWA open with no connection (#34).
//
// Flutter no longer ships one that caches — on 3.44 its
// flutter_service_worker.js unregisters itself — and hosting sends
// `Cache-Control: no-cache`, so without this a launch with no signal gets
// nothing at all. Once the app is open, Firestore's own cache supplies the
// data and queues writes; this only has to get the app itself on screen.
//
// Two caches:
//
//  * The shell — this build's own files, fetched together when the worker
//    installs and served from the cache from then on, navigations included.
//    One version, kept whole: index.html from one deploy running
//    main.dart.js from another is a broken app, so the page is never mixed
//    from the network and the cache. A new deploy installs a new worker in
//    the background; the app offers "Update available · Reload" and the new
//    version takes over on that reload.
//
//  * The CDN — what Flutter and Firebase load from Google's servers rather
//    than from ours: CanvasKit, the Firebase JS SDK, and the fallback fonts.
//    Each sits under a versioned path and never changes, so it is served
//    from the cache once it is there.
//
// Everything else — Firestore, Auth, push, any other API — is not touched:
// Firestore has its own offline handling, and a cached API answer would be
// a wrong one.
//
// web/app_sw.js is a template. The deploy fills in the two values below
// from the finished build (tool/stamp_service_worker.dart); unfilled, as
// under `flutter run`, the worker installs and does nothing.

const VERSION = '__APP_VERSION__';
const SHELL = /* __APP_SHELL__ */ [];

const SHELL_CACHE = `shell-${VERSION}`;
const CDN_CACHE = 'cdn';

/// Where the CDN files come from. Prefixes, each followed by a version
/// directory for the two that have one.
const CDN = [
  'https://www.gstatic.com/flutter-canvaskit/',
  'https://www.gstatic.com/firebasejs/',
  'https://fonts.gstatic.com/',
];

const stamped = !VERSION.startsWith('__');

self.addEventListener('install', (event) => {
  if (!stamped) return;
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL_CACHE);
      // From the network, not the browser's HTTP cache, so every file is
      // this deploy's.
      await cache.addAll(SHELL.map((path) => new Request(path, { cache: 'reload' })));
      // The first install has no older version to wait for: take over now,
      // so this very visit is the one that fills the CDN cache.
      if (!self.registration.active) await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const name of await caches.keys()) {
        if (name.startsWith('shell-') && name !== SHELL_CACHE) {
          await caches.delete(name);
        }
      }
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type === 'skip-waiting') {
    // The person tapped Reload: this version takes over, and the page
    // reloads into it on `controllerchange`.
    self.skipWaiting();
  } else if (data.type === 'warm' && Array.isArray(data.urls)) {
    event.waitUntil(warm(data.urls));
  }
});

self.addEventListener('fetch', (event) => {
  if (!stamped) return;
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (url.origin === self.location.origin) {
    // Hosting's own reserved paths: the sign-in helper and its iframe.
    // They have to come from the server.
    if (url.pathname.startsWith('/__/')) return;

    if (request.mode === 'navigate') {
      // Any page of the app is index.html; the router does the rest.
      event.respondWith(fromShell('index.html', request));
      return;
    }
    const path = url.pathname.replace(/^\//, '');
    if (SHELL.includes(path)) {
      event.respondWith(fromShell(path, request));
    }
    // Anything else of ours — the licences, a CanvasKit variant served
    // locally — goes to the network as it would without a worker.
    return;
  }

  if (isCdn(request.url)) {
    event.respondWith(fromCdn(request));
  }
  // Anything else cross-origin is an API: left alone.
});

/// The shell's copy of [path], or the network's if, somehow, there is
/// none.
async function fromShell(path, request) {
  const cache = await caches.open(SHELL_CACHE);
  const hit = await cache.match(path);
  return hit || fetch(request);
}

function isCdn(url) {
  return CDN.some((prefix) => url.startsWith(prefix));
}

/// Cache first; on a miss, the network, kept for next time.
async function fromCdn(request) {
  const cache = await caches.open(CDN_CACHE);
  const hit = await cache.match(request.url, { ignoreVary: true });
  if (hit) return hit;
  const response = await fetch(request);
  if (response.ok && (response.type === 'cors' || response.type === 'basic')) {
    await cache.put(request.url, response.clone());
  }
  return response;
}

/// Caches the CDN files a page has already loaded, from the list it sends.
///
/// The first visit loads CanvasKit and Firebase before this worker is
/// running, so nothing intercepted them; the page reports them once it is
/// up. They are in the browser's HTTP cache by then, so this costs little.
///
/// Also where old versions go: a CanvasKit or Firebase directory the page
/// no longer uses is a few megabytes nothing will ask for again.
async function warm(urls) {
  const wanted = urls.filter(isCdn);
  const cache = await caches.open(CDN_CACHE);
  for (const url of wanted) {
    if (await cache.match(url, { ignoreVary: true })) continue;
    try {
      const response = await fetch(url, { mode: 'cors', credentials: 'omit' });
      if (response.ok) await cache.put(url, response);
    } catch (_) {
      // Offline, or the CDN refused: the next visit will try again.
    }
  }
  await prune(cache, wanted);
}

/// Drops cached CDN files from versions the page did not load, for the
/// versioned families it did — never guessing about a family it did not
/// report on.
async function prune(cache, wanted) {
  const inUse = new Map();
  for (const url of wanted) {
    const dir = versionDir(url);
    if (dir) inUse.set(dir.family, dir.path);
  }
  for (const request of await cache.keys()) {
    const dir = versionDir(request.url);
    if (dir && inUse.has(dir.family) && inUse.get(dir.family) !== dir.path) {
      await cache.delete(request);
    }
  }
}

/// "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js" →
/// family "https://www.gstatic.com/firebasejs/", path ".../10.12.2/".
function versionDir(url) {
  for (const family of CDN.slice(0, 2)) {
    if (!url.startsWith(family)) continue;
    const rest = url.slice(family.length);
    const slash = rest.indexOf('/');
    if (slash < 0) return null;
    return { family, path: family + rest.slice(0, slash + 1) };
  }
  return null;
}
