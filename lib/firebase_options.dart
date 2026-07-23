// PLACEHOLDER — replace by running `flutterfire configure` (see README).
//
// That command generates the real FirebaseOptions for each platform from
// your Firebase project and overwrites this file. Until then the app will
// throw at startup so the missing configuration is obvious.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured yet. Run `flutterfire configure` to '
      'generate lib/firebase_options.dart, then restart the app.',
    );
  }
}
