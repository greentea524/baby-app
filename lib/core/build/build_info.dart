/// Which build of the app this is, stamped in by the deploy.
///
/// The commit the web build was made from, shortened, and when. Shown in
/// Settings so two devices can be compared at a glance: a home-screen app
/// on a phone can go on running yesterday's build until it is fully closed,
/// and two devices disagreeing is often one of them being behind.
///
/// "dev" for a build made without them — a local run, or a test.
const String appBuild = String.fromEnvironment(
  'APP_BUILD',
  defaultValue: 'dev',
);

const String appBuiltAt = String.fromEnvironment('APP_BUILT_AT');

/// "Version 3f2a9c1 · built 2026-10-02 14:31 UTC", or "Version dev".
String get appVersionLine => appBuiltAt.isEmpty
    ? 'Version $appBuild'
    : 'Version $appBuild · built $appBuiltAt';
