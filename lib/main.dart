import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/launch_action.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_accent.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/web/loading_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Offline persistence: caches Firestore data locally (IndexedDB on web)
  // so the PWA works offline and syncs on reconnect.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  final prefs = await SharedPreferences.getInstance();

  // A PWA shortcut launches at e.g. /?action=feed (KAN-166).
  final launchAction = Uri.base.queryParameters['action'];

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialLaunchActionProvider.overrideWithValue(launchAction),
      ],
      child: const BabyApp(),
    ),
  );

  // Everything above this line happens behind the HTML loading screen: the
  // engine boot, then Firebase and the stored preferences awaited here. Take
  // it down only once there is a real frame behind it.
  WidgetsBinding.instance.addPostFrameCallback((_) => dismissLoadingScreen());
}

class BabyApp extends ConsumerWidget {
  const BabyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final seed = ref.watch(accentProvider).seed;

    return MaterialApp.router(
      title: 'Baby App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(seed),
      darkTheme: AppTheme.dark(seed),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
