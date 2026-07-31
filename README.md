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

## Run

```bash
flutter run -d chrome
```

## Build the PWA

```bash
flutter build web
```

Output is in `build/web/` (installable — includes manifest + service worker).

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

## Background push notifications (KAN-156) — optional, requires setup

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
   It runs every 15 minutes: for each baby it predicts the next feed from a
   rolling average of recent intervals and pushes caregivers whose device
   token is registered (`fcmTokens/{token}`).
4. In the app, open **Settings → Background reminders** and toggle it on to
   grant notification permission and register this device.

The in-app "next feed" reminder card works with none of this; the above only
adds notifications when the app isn't open.
