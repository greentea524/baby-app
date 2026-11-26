import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/models/care_stay.dart';
import '../../data/models/feeding_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../home/home_status_card.dart' show dueLine;
import '../reminders/feed_prediction.dart'
    show DueState, countdownLabel, drivesFeedClock;

/// The most automatic feeds one pass will log: two days of hourly feeds. A
/// stay left open for a week fills in a day or two at a time rather than
/// writing hundreds in one go.
const int autoFeedCap = 48;

/// When [stay]'s automatic feeds fall, up to [until].
///
/// Each is a feed interval after the one before, starting from the last feed
/// that drives the feed clock — [lastFeed], which may be an automatic one or
/// one logged by hand while away (a text from Grandma saying she fed at
/// 10:30 moves the next one to 1:30).
///
/// Never before drop-off: a baby already overdue when dropped off has the
/// first one at drop-off itself. Never at or before [CareStay.autoUntil]: a
/// feed the app logged and someone then deleted is not put back.
List<DateTime> autoFeedTimes({
  required CareStay stay,
  required DateTime? lastFeed,
  required DateTime until,
  int cap = autoFeedCap,
}) {
  if (!stay.autoFeed || stay.intervalMinutes <= 0) return const [];
  final end = stay.pickedUpAt != null && stay.pickedUpAt!.isBefore(until)
      ? stay.pickedUpAt!
      : until;
  var t = (lastFeed ?? stay.droppedAt).add(stay.interval);
  if (t.isBefore(stay.droppedAt)) t = stay.droppedAt;
  final done = stay.autoUntil;
  if (done != null) {
    while (!t.isAfter(done)) {
      t = t.add(stay.interval);
    }
  }
  final times = <DateTime>[];
  while (!t.isAfter(end) && times.length < cap) {
    times.add(t);
    t = t.add(stay.interval);
  }
  return times;
}

/// The feed logged automatically at [at] during [stay].
FeedingEvent autoFeedAt(CareStay stay, DateTime at) => FeedingEvent(
  id: autoFeedId(stay, at),
  type: FeedingType.bottle,
  startTime: at,
  amountMl: stay.amountMl,
  milk: stay.milk,
  notes: stay.carer.trim().isEmpty
      ? 'Auto-logged while away'
      : 'Auto-logged · with ${stay.carer.trim()}',
);

/// The document id of the feed logged automatically at [at] during [stay].
///
/// Named rather than generated, so two devices filling in the same feed at
/// once write one document between them, not two.
String autoFeedId(CareStay stay, DateTime at) =>
    '${stay.autoFeedPrefix}${at.millisecondsSinceEpoch}';

/// Whether [feed] was logged by the app while the baby was away.
bool isAutoFeed(FeedingEvent feed) => feed.id.startsWith('auto-');

/// Logs [stay]'s automatic feeds due up to [until], and returns how many it
/// wrote.
///
/// In a transaction: the stay is read fresh, so a pick-up or another
/// device's pass since is seen, and each feed is written only if it is not
/// there already. [CareStay.autoUntil] moves on with them.
///
/// Online only. Offline the transaction throws, and the next pass — on this
/// device or any other — fills them in at the right times all the same.
Future<int> logAutoFeeds({
  required FirebaseFirestore firestore,
  required String babyId,
  required String uid,
  required String stayId,
  required DateTime? lastFeed,
  required DateTime until,
}) {
  final baby = firestore.collection('babies').doc(babyId);
  final stayRef = baby.collection('stays').doc(stayId);
  return firestore.runTransaction<int>((txn) async {
    final snap = await txn.get(stayRef);
    if (!snap.exists) return 0;
    final stay = CareStay.fromDoc(snap);
    final times = autoFeedTimes(stay: stay, lastFeed: lastFeed, until: until);
    if (times.isEmpty) return 0;

    final refs = [
      for (final t in times)
        baby.collection('feedings').doc(autoFeedId(stay, t)),
    ];
    final existing = [for (final ref in refs) await txn.get(ref)];

    var written = 0;
    for (var i = 0; i < times.length; i++) {
      if (existing[i].exists) continue;
      txn.set(refs[i], {
        ...autoFeedAt(stay, times[i]).toMap(),
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      written++;
    }
    txn.update(stayRef, {
      'autoUntil': Timestamp.fromDate(times.last),
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return written;
  });
}

/// The last feed that drives the feed clock, from the newest-first [feeds].
DateTime? lastClockFeed(List<FeedingEvent> feeds) {
  for (final f in feeds) {
    if (drivesFeedClock(f)) return f.startTime;
  }
  return null;
}

/// Fills in the current stay's automatic feeds while the app is open: when
/// it starts, whenever the stay or the feeds change, and once a minute.
///
/// Watched from the app's root. Any device with the app open does it; with
/// none open the next one to open catches up, at the right times.
final autoFeederProvider = Provider<AutoFeeder>((ref) {
  final feeder = AutoFeeder(ref);
  ref.onDispose(feeder.dispose);
  return feeder;
});

class AutoFeeder {
  AutoFeeder(this._ref) {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => run());
    _ref.listen(activeStayProvider, (_, _) => run());
    _ref.listen(recentFeedingsProvider, (_, _) => run());
    Future.microtask(run);
  }

  final Ref _ref;
  Timer? _timer;
  bool _running = false;

  /// One pass, up to [until] — now, unless a pick-up is closing the stay.
  Future<int> run({DateTime? until, CareStay? stay}) async {
    if (_running) return 0;
    final current = stay ?? _ref.read(activeStayProvider);
    final user = _ref.read(authStateProvider).value;
    final baby = _ref.read(currentBabyProvider);
    if (current == null || !current.autoFeed || user == null || baby == null) {
      return 0;
    }
    final feeds = _ref.read(recentFeedingsProvider).value;
    if (feeds == null) return 0;
    final end = until ?? DateTime.now();
    if (autoFeedTimes(
      stay: current,
      lastFeed: lastClockFeed(feeds),
      until: end,
    ).isEmpty) {
      return 0;
    }
    _running = true;
    try {
      return await logAutoFeeds(
        firestore: _ref.read(firestoreProvider),
        babyId: baby.id,
        uid: user.uid,
        stayId: current.id,
        lastFeed: lastClockFeed(feeds),
        until: end,
      );
    } catch (_) {
      // Offline, or refused. The next pass tries again.
      return 0;
    } finally {
      _running = false;
    }
  }

  void dispose() => _timer?.cancel();
}

/// The feed clock's state while [stay] has feeds logged automatically: never
/// past due. The app logs the feed at the due time itself, so for the minute
/// before it does, red would be a false alarm.
DueState feedStateWhileAway(DueState state, CareStay? stay) =>
    stay != null && stay.autoFeed && state.isPast ? DueState.soon : state;

/// The diaper clock's state while [stay] lasts: nothing. Nobody at home can
/// change the baby, so a row turning red then purple asks for what cannot
/// be done.
DueState? diaperStateWhileAway(DueState? state, CareStay? stay) =>
    stay != null ? null : state;

/// The feed countdown's words while feeds are logged automatically: when the
/// next one will be logged, or, past its time, that it is being logged — not
/// "overdue", which asks someone at home to do something.
String autoFeedLine(DateTime due, DateTime now, String at) => due.isAfter(now)
    ? dueLine('Next auto feed', countdownLabel(due, now: now), at)
    : dueLine('Auto feed', 'logging now', at);
