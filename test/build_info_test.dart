import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/core/build/build_info.dart';

/// The version line Settings shows, for comparing two devices.
void main() {
  test('a build made without the stamp says it is a dev build', () {
    // The deploy passes APP_BUILD and APP_BUILT_AT; a test run does not.
    expect(appBuild, 'dev');
    expect(appVersionLine, 'Version dev');
  });
}
