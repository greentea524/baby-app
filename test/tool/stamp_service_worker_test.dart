import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/stamp_service_worker.dart';

/// The build step that fills in web/app_sw.js (#34).
void main() {
  group('fnv1a64', () {
    test('matches the published test values', () {
      expect(fnv1a64([]), 'cbf29ce484222325');
      expect(fnv1a64(utf8.encode('a')), 'af63dc4c8601ec8c');
      expect(fnv1a64(utf8.encode('foobar')), '85944171f73967e8');
    });
  });

  group('the shell', () {
    test('is the app, not CanvasKit, the licences or the workers', () {
      for (final path in [
        'index.html',
        'main.dart.js',
        'flutter.js',
        'flutter_bootstrap.js',
        'manifest.json',
        'icons/Icon-192.png',
        'assets/FontManifest.json',
        'assets/fonts/MaterialIcons-Regular.otf',
      ]) {
        expect(isShellFile(path), isTrue, reason: path);
      }
      for (final path in [
        'canvaskit/canvaskit.wasm',
        'canvaskit/chromium/canvaskit.js',
        'main.dart.js.symbols',
        'assets/NOTICES',
        'app_sw.js',
        'firebase-messaging-sw.js',
        'flutter_service_worker.js',
        '.last_build_id',
      ]) {
        expect(isShellFile(path), isFalse, reason: path);
      }
    });

    test('changes version when any file does, and only then', () {
      final a = [
        (path: 'index.html', bytes: utf8.encode('<html>')),
        (path: 'main.dart.js', bytes: utf8.encode('main()')),
      ];
      final same = [
        (path: 'index.html', bytes: utf8.encode('<html>')),
        (path: 'main.dart.js', bytes: utf8.encode('main()')),
      ];
      final edited = [
        (path: 'index.html', bytes: utf8.encode('<html>')),
        (path: 'main.dart.js', bytes: utf8.encode('main() ')),
      ];
      // The same bytes under another name is another build.
      final renamed = [
        (path: 'index.htm', bytes: utf8.encode('l<html>')),
        (path: 'main.dart.js', bytes: utf8.encode('main()')),
      ];
      expect(shellVersion(a), shellVersion(same));
      expect(shellVersion(a), isNot(shellVersion(edited)));
      expect(shellVersion(a), isNot(shellVersion(renamed)));
    });
  });

  group('stamp', () {
    final template = File('web/app_sw.js').readAsStringSync();

    test('fills in the real worker template', () {
      final out = stamp(
        template,
        version: '0123456789abcdef',
        paths: ['index.html', 'main.dart.js'],
      );
      expect(out, contains("const VERSION = '0123456789abcdef';"));
      expect(out, contains('"index.html"'));
      expect(out, isNot(contains('__APP_')));
    });

    test('refuses to stamp twice', () {
      final once = stamp(template, version: 'v', paths: const []);
      expect(
        () => stamp(once, version: 'v', paths: const []),
        throwsStateError,
      );
    });
  });
}
