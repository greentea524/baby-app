import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The PWA manifest, checked because nothing else reads it (#29).
///
/// It is JSON in `web/`, so no widget test loads it and a typo there is
/// invisible until an installed app misbehaves on someone's device.
void main() {
  final manifest =
      jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;

  test('does not lock the app to portrait', () {
    // It was "portrait-primary", which an installed PWA honours — so the
    // iPad simply refused to rotate, whatever the layouts could handle.
    expect(manifest['orientation'], 'any');
  });

  test('still installs as an app rather than a browser tab', () {
    // The rest of the manifest is what makes nursery mode worth having on a
    // stand: no address bar, no tab strip.
    expect(manifest['display'], 'standalone');
    expect(manifest['name'], isNotEmpty);
    expect(manifest['icons'], isNotEmpty);
  });

  test('keeps the quick-log shortcuts', () {
    final shortcuts = manifest['shortcuts'] as List<dynamic>;
    expect(
      shortcuts.map((s) => (s as Map<String, dynamic>)['url']),
      containsAll(<String>['./?action=feed', './?action=diaper']),
    );
  });
}
