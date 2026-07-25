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

## Test & analyze

```bash
flutter analyze
flutter test
```

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
