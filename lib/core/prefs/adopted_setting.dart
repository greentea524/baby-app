/// Merging one setting that is stored both on the device and on the account.
library;

/// Which value wins when this device's setting and the account's disagree —
/// the value to adopt, or null to keep the device's own.
///
/// Settings like this are stored twice: locally, which is what the in-app UI
/// reads with no loading state and no network, and on the account, which is
/// what other devices and the reminder Cloud Function read. Only the local
/// copy was ever read back, so a second device kept showing its own stale
/// feed interval — or the 3-hour default, on a device that had never set one
/// — while push reminders used the account's (#27).
///
/// Neither copy carries a timestamp, so "newest wins" is not available. What
/// is available is whether this device is carrying a change that never landed:
///
/// | chosen | lastSynced | server | outcome           |
/// |--------|-----------|--------|-------------------|
/// | unset  | —         | 240    | adopt 240         |
/// | 240    | 240       | 300    | adopt 300         |
/// | 240    | 240       | 240    | keep — they agree |
/// | 240    | unset/180 | 180    | keep 240, resync  |
///
/// A device that has chosen something the account has not acknowledged is the
/// one holding the newer value, so it wins and pushes again. Otherwise the
/// account wins, because any difference came from somewhere else.
///
/// Lives here rather than with the feed reminder that first needed it: the
/// pump interval syncs the same way, and the rule is about two copies of a
/// value, not about reminders.
T? adoptedSetting<T>({
  required T? chosen,
  required T? lastSynced,
  required T server,
}) {
  if (chosen != null && chosen != lastSynced) return null;
  if (server == chosen) return null;
  return server;
}
