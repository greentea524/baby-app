# Baby App

A Flutter **web / PWA** for tracking a baby's feeding, diaper changes, and growth,
with Google sign-in and real-time sync across caregivers (Firebase Auth + Firestore).

## Stack

| Concern | Choice |
|---|---|
| UI / platform | Flutter Web (installable PWA); mobile targets ready to add |
| State management | Riverpod |
| Routing | go_router (auth-gated redirect) |
| Auth | Firebase Auth — Google sign-in |
| Data | Cloud Firestore, offline persistence enabled |
| Theme | Material 3, light/dark/system (persisted via shared_preferences) |

## Project layout

```
lib/
  core/
    auth/        # AuthRepository + Riverpod providers, auth state stream
    router/      # go_router config with login redirect guard
    theme/       # light/dark themes + persisted ThemeMode
  data/
    models/      # Baby, FeedingEvent, DiaperEvent (Firestore serialization)
    repositories/# Firestore repositories, scoped under users/{uid}
  features/
    auth/        # LoginScreen (Google sign-in)
    home/        # Home dashboard (feeding quick-log lands in KAN-130)
    timeline/    # Event timeline (KAN-132)
    settings/    # Appearance / theme switch
  firebase_options.dart   # PLACEHOLDER — regenerate (see below)
  main.dart
```

### Firestore data model

Everything is scoped under the signed-in user so security rules stay simple:

```
users/{uid}/babies/{babyId}
users/{uid}/babies/{babyId}/feedings/{eventId}
users/{uid}/babies/{babyId}/diapers/{eventId}
```

## One-time setup — connect Firebase (required)

The app **will not start** until Firebase is configured (`firebase_options.dart`
is currently a placeholder that throws on purpose). Do this once:

1. Create a project at <https://console.firebase.google.com>.
2. In **Authentication → Sign-in method**, enable **Google**.
3. Install the CLIs (once per machine):
   ```bash
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   ```
4. From the project root, generate the real config:
   ```bash
   flutterfire configure
   ```
   This overwrites `lib/firebase_options.dart` with your project's values.
5. Add your dev/prod domains under **Authentication → Settings → Authorized
   domains** (`localhost` is allowed by default).

## Who can use it — the invite allowlist

The app is private. Google sign-in itself cannot be restricted to a list of
addresses, so anyone can *sign in* — but without an entry in `allowedUsers`
they cannot create a baby, and they were never able to read one they are not a
member of. Signing in uninvited gets you a locked door, not a free tracker on
someone else's bill.

Two separate ways in, deliberately:

| | Who it covers | How they get in |
|---|---|---|
| `allowedUsers/{email}` | People who may **start** a household of their own | A document you create by hand |
| `babies/{babyId}/invites/{email}` | Caregivers joining an **existing** baby | The owner invites them in-app |

An invitee never needs an allowlist entry — accepting an invite is an update to
a baby the owner already vouched for. Only starting from nothing is gated.

To let a new address start its own household, create a document in the Firebase
console — **Firestore Database → Data → Start collection** `allowedUsers` — whose
**document ID is the lowercased email**, e.g. `someone@example.com`. The
document needs no fields; only its existence is checked. (There is no CLI
command for writing a single document; the console is the way.)

No email addresses live in this repository. The rules match on
`request.auth.token.email` against whatever documents exist, so the list is
data, not code — which is what keeps a public repo from publishing the guest
list. Rules let each signed-in user read **only their own** entry, so the
collection cannot be enumerated either.

Removing the document stops that address starting *new* households; it does not
evict them from babies they already belong to. Remove them from the baby's
caregiver list for that.

## Run

```bash
flutter run -d chrome
```

## Build the PWA

```bash
flutter build web
```

Output is in `build/web/` (installable — includes the manifest and icons).

### The loading screen

Opening the installed PWA is several seconds of work before Flutter can paint:
`main.dart.js` is ~1.1 MB gzipped and has to be parsed, CanvasKit is a ~2.8 MB
gzipped wasm module to fetch and compile, and then `main()` awaits Firebase and
the stored preferences. Stock Flutter shows a blank page for all of it.

`web/index.html` carries a loading screen — the app icon on the manifest's
`background_color`, so the Android splash hands over without a colour change —
and `web/flutter_bootstrap.js` takes it down.

The dismissal is triggered from Dart (`lib/core/web/loading_screen.dart`), not
from the bootstrap's own `runApp()` promise: that promise resolves once `main()`
is *invoked*, which is still before Firebase has initialised and before anything
has rendered. The bootstrap also arms a 25-second failsafe, outside the loader's
awaits, since a boot that fails usually fails by never returning.

Both files are stock Flutter templates with local edits, so re-running
`flutter create` over this project would discard them.

## Native mobile builds (Android / iOS)

The `android/` and `ios/` projects are scaffolded and the auth code already
handles native sign-in (`signInWithProvider`), but **native builds will not
run until you generate the platform Firebase config** — `firebase_options.dart`
deliberately throws for every non-web platform, and the config files contain
project-specific keys that can't be committed generically.

1. Register the apps: `flutterfire configure` and select **android** and
   **ios** alongside web. This rewrites `lib/firebase_options.dart` and drops
   `android/app/google-services.json` + `ios/Runner/GoogleService-Info.plist`.
2. **Android** — add your signing SHA-1 and SHA-256 under Firebase console →
   Project settings → your Android app. Google sign-in fails without them:
   ```bash
   cd android && ./gradlew signingReport
   ```
3. **iOS** — add the reversed client ID from `GoogleService-Info.plist` as a
   URL scheme in `ios/Runner/Info.plist`, so the OAuth redirect can return to
   the app.
4. Run:
   ```bash
   flutter run -d android
   flutter run -d ios
   ```

The generated config files are gitignored by default — keep them out of the
repo and regenerate per machine.

## Test & analyze

```bash
flutter analyze
flutter test
```

### Firestore security rules tests

`firestore.rules` carries all the multi-caregiver access control, so it has
its own emulator-backed suite in `rules-tests/`:

```bash
cd rules-tests && npm install && npm test
```

This boots the Firestore emulator, runs the real rules against it, and checks
that non-members are locked out, that only the owner can delete a profile or
manage invites, that invite acceptance can't be forged, and that FCM tokens
stay private.

Run it after any rules edit. The wildcard `match /{sub}/{docId}` covers every
subcollection, and Firestore allows an operation if **any** rule permits it —
so a narrower rule written above it can be silently overridden by the wildcard
below. The suite catches that; reading the rules does not.

Passing tests only mean the rules are correct, not that they are live — see
[deploying them](#security-rules-deploy-by-hand).

## Continuous deployment

`.github/workflows/deploy.yml` builds and deploys to Firebase Hosting on
every push to `main` (after `flutter analyze` + `flutter test` pass). Pull
requests run checks only, via `ci.yml`.

**One-time setup** — add a Firebase service-account key as a repo secret so
the Action can deploy:

1. Firebase console → **Project settings → Service accounts → Generate new
   private key** — downloads a JSON file.
2. Store it as the `FIREBASE_SERVICE_ACCOUNT` secret (don't commit it):
   ```bash
   gh secret set FIREBASE_SERVICE_ACCOUNT --repo greentea524/baby-app < path/to/serviceAccountKey.json
   ```

After that, `git push` to `main` deploys the **app** automatically. (To also
inject the push VAPID key, add `--dart-define=VAPID_KEY=${{ secrets.VAPID_KEY }}`
to the build step and set that secret too.)

### Security rules deploy by hand

The workflow runs `action-hosting-deploy`, which publishes `build/web` and
nothing else. **Changes to `firestore.rules` do not ship with it** — merging a
rules change to `main` leaves `main` looking correct while the old rules are
still the ones enforced in production. Deploy them yourself:

```bash
firebase deploy --only firestore:rules
```

`.firebaserc` in the repo root points the CLI at the project, so no `--project`
flag is needed. It only maps an alias to a project ID — nothing secret — which
is why it is committed rather than left for each machine to recreate.

If you ever see *"No currently active project"*, that file is missing or you
are running from outside the repo root. Pass the project for one command:

```bash
firebase deploy --only firestore:rules --project baby-6f5b0
```

or recreate the file with `firebase use --add`, picking the project and
aliasing it `default`. Note that `--project` is a one-off flag and writes
nothing — only `firebase use --add` creates `.firebaserc`.

Afterwards, confirm the change is live in the Firebase console under
**Firestore → Rules**, which shows the ruleset actually in force. The same
applies to `firestore.indexes.json` (`--only firestore:indexes`) and to the
reminder function in `functions/` (`npm run deploy`).

#### Deploy the app before the rules, not after

Rules validate what gets written (#22), so a rule that is stricter than the
running client rejects writes the client still thinks are fine — and since
sheets no longer wait for the write (#21), the caregiver sees the entry save
and gets an error minutes later. Ship the app first, then the rules.

The reverse order is safe only when a rules change is purely a loosening.
`rules-tests/` has a whole `describe("what the app writes today")` block whose
job is to fail if a rule stops accepting a payload the client still sends —
run `npm test` in `rules-tests/` before deploying either half.

### Why `authDomain` follows the page rather than the project

`sameOriginAuth` in `lib/core/auth/auth_domain.dart` rewrites the generated
`authDomain` to whatever host is serving the page, and `main.dart` passes every
`FirebaseOptions` through it. This is deliberate — do not "fix" it back to the
value `flutterfire configure` writes.

Firebase Auth does its browser work through a helper served at `/__/auth/` on
the `authDomain`. Generated, that is `<project>.firebaseapp.com`, which is a
*third party* to a page served from `<project>.web.app` or a custom domain — and
Safari will not give a third party IndexedDB, where Firebase Auth keeps the
session. Signing in on an iPhone failed with `An unknown error occurred: Error:
Database is closing/hidden [unknown]` on exactly that.

Firebase Hosting serves `/__/auth/` on every site in the project, so following
the page's own host makes the helper same-origin whatever domain is in use.
`localhost` is excluded: a dev server is not Hosting and serves no helper, so it
keeps the generated domain.

Any host the app is served from must be listed under **Authentication →
Settings → Authorized domains**. `web.app` and `firebaseapp.com` are there by
default; a custom domain has to be added, and forgetting shows up as
`unauthorized-domain`.

Mobile browsers also sign in by redirect rather than popup
(`AuthRepository.redirectSignIn`): a popup backgrounds the page that opened it,
and iOS closes a hidden page's IndexedDB connections. The two changes go
together and in that order — `signInWithRedirect` is *more* dependent on a
same-origin helper than the popup was, so redirecting without the domain fix
would make an iPhone worse rather than better.

### Why hosting sends `Cache-Control: no-cache`

`firebase.json` sets `no-cache` on every hosted file. Without it, Hosting
defaults to `max-age=3600` on *everything* — including `index.html` and
`flutter_service_worker.js` — so a returning device wouldn't even ask whether
a new build exists until an hour after a deploy.

`no-cache` means "revalidate before using", not "don't store". Hosting sends
strong ETags, so unchanged files come back as tiny `304`s and the service
worker still serves assets from the Cache API. It applies to everything
because none of Flutter's web output is content-hashed in its filename
(`main.dart.js` is always `main.dart.js`), so a stale HTTP cache can hand the
service worker an old copy of a file it is trying to update.

Note that even with this, the service worker activates a new build on the
*next* load — so a returning visitor sees the previous version once. That is
inherent to how the Flutter service worker updates, not something the headers
can fix.

## Background push notifications (KAN-156) — built, not deployed

> **Status: dormant.** The code is complete and merged, but the Cloud Function
> has never been deployed, so **the live app does not send notifications** and
> the reminder switches are hidden. Nothing here is described as a feature of
> the running app — treat it as ready to enable, not as working.
>
> Kept rather than deleted because enabling it is a billing decision, not a
> development one: the three steps below are all that stand between this and
> working. Do not describe it as a shipped feature until they are done.

Feed reminders can be delivered while the app is closed, via Firebase Cloud
Messaging + a scheduled Cloud Function. This needs a few one-time steps that
**can't be automated** (billing + a device permission):

1. **Upgrade to the Blaze plan** — Cloud Functions require it (there's a free
   tier; a scheduled 15-min job is well within it).
2. **Generate a Web Push key** — Firebase console → Project settings → Cloud
   Messaging → *Web configuration* → **Generate key pair**. Build the web app
   with it:
   ```bash
   flutter build web --dart-define=VAPID_KEY=<your-web-push-public-key>
   ```
3. **Deploy the function** (the reminder engine, in `functions/`):
   ```bash
   cd functions && npm install && npm run deploy
   ```
   It runs every 15 minutes: for each baby it takes the last feed that resets
   the clock — skipping snacks and solids — adds each caregiver's own reminder
   interval, and pushes anyone now overdue whose device token is registered
   (`fcmTokens/{token}`), respecting their quiet hours and grace period.
4. In the app, open **Settings → Background reminders** and toggle it on to
   grant notification permission and register this device.

### Why the reminder switches may not be there

**Settings → Background reminders** and **Quiet hours** are hidden unless the
build carries a `VAPID_KEY`. Both only govern pushes sent by the function
above, so without that setup they are switches with nothing behind them — and
quiet hours would read "no reminders 10 PM – 7 AM" when no reminder can arrive
at any hour. Supplying the key at build time (step 2) brings both back;
`backgroundRemindersAvailable` in `lib/features/notifications/push_service.dart`
is the single check.

The key stands in for the whole setup because it is the part the app can see.
It does **not** prove the function is deployed — if the switches appear but no
notification ever arrives, check step 3.

The in-app "next feed" chip works with none of this: it is computed on the
device from the last feed plus your chosen interval. The above only adds
notifications when the app isn't open.
