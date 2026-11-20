import 'package:baby_app/core/theme/theme_mode_provider.dart';
import 'package:baby_app/core/web/install_hint.dart';
import 'package:baby_app/features/auth/login_screen.dart';
import 'package:baby_app/features/install/install_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _iPhoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 '
    'Safari/604.1';
const _iPhoneOld =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.3 Mobile/15E148 '
    'Safari/604.1';
const _iPhoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.6778.73 '
    'Mobile/15E148 Safari/604.1';
const _iPhoneInstagram =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
    'Instagram 357.0.0.0';
const _iPhoneGmail =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
const _mac =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.1 Safari/605.1.15';
const _android =
    'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

IosInstallHint? _hint(String ua, {int touch = 5, bool standalone = false}) =>
    iosInstallHint(
      userAgent: ua,
      maxTouchPoints: touch,
      standalone: standalone,
    );

void main() {
  group('iosInstallHint', () {
    test('Safari on iPhone gets the Safari steps', () {
      expect(
        _hint(_iPhoneSafari),
        const IosInstallHint(
          browser: IosBrowser.safari,
          notificationsSupported: true,
        ),
      );
    });

    test('nothing once it is opened from the Home Screen', () {
      expect(_hint(_iPhoneSafari, standalone: true), isNull);
    });

    test('nothing on Android or a Mac', () {
      expect(_hint(_android), isNull);
      // A Mac reports no touch points; that is what sets an iPad apart.
      expect(_hint(_mac, touch: 0), isNull);
    });

    test('an iPad asking for the desktop site is still an iPad', () {
      expect(_hint(_mac, touch: 5)?.browser, IosBrowser.safari);
    });

    test('Chrome on iPhone is told where its Share button is', () {
      expect(_hint(_iPhoneChrome)?.browser, IosBrowser.otherBrowser);
    });

    test('in-app browsers are sent to Safari first', () {
      expect(_hint(_iPhoneInstagram)?.browser, IosBrowser.inApp);
      expect(_hint(_iPhoneGmail)?.browser, IosBrowser.inApp);
    });

    test('before iOS 16.4 the reminders are not promised', () {
      expect(_hint(_iPhoneOld)?.notificationsSupported, isFalse);
      expect(_hint(_iPhoneSafari)?.notificationsSupported, isTrue);
    });
  });

  group('InstallBanner', () {
    const hint = IosInstallHint(
      browser: IosBrowser.safari,
      notificationsSupported: true,
    );

    Future<SharedPreferences> prefs() async {
      SharedPreferences.setMockInitialValues({});
      return SharedPreferences.getInstance();
    }

    testWidgets('the login screen says to add it before signing in', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [iosInstallHintProvider.overrideWithValue(hint)],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      expect(find.textContaining('then sign in from there'), findsOneWidget);
      // Not something to put away here: signing in first only means
      // signing in twice.
      expect(find.text('Not now'), findsNothing);
      // Above the button it is advice about.
      expect(
        tester.getTopLeft(find.text('Show me how')).dy,
        lessThan(tester.getTopLeft(find.text('Continue with Google')).dy),
      );
    });

    testWidgets('and is absent everywhere else', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );
      expect(find.text('Show me how'), findsNothing);
    });

    testWidgets('Home\'s banner stays put away once dismissed', (tester) async {
      final sp = await prefs();
      Widget app() => ProviderScope(
        overrides: [
          iosInstallHintProvider.overrideWithValue(hint),
          sharedPreferencesProvider.overrideWithValue(sp),
        ],
        child: const MaterialApp(home: Scaffold(body: InstallBanner())),
      );

      await tester.pumpWidget(app());
      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(find.text('Show me how'), findsNothing);

      // A fresh start on the same device.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      expect(find.text('Show me how'), findsNothing);
    });

    testWidgets('Show me how opens the steps for this browser', (tester) async {
      final sp = await prefs();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iosInstallHintProvider.overrideWithValue(
              const IosInstallHint(
                browser: IosBrowser.inApp,
                notificationsSupported: true,
              ),
            ),
            sharedPreferencesProvider.overrideWithValue(sp),
          ],
          child: const MaterialApp(home: Scaffold(body: InstallBanner())),
        ),
      );
      await tester.tap(find.text('Show me how'));
      await tester.pumpAndSettle();

      expect(find.text('Add to Home Screen'), findsOneWidget);
      expect(find.textContaining('Open in Safari'), findsOneWidget);
    });
  });
}
