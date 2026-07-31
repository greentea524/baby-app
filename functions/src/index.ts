// DORMANT — this function has never been deployed.
//
// It is complete and kept deliberately: enabling it is a billing decision (the
// Blaze plan) rather than a development one. Until `npm run deploy` is run
// against a Blaze project, the app sends no background notifications, and the
// reminder switches in Settings stay hidden — see `backgroundRemindersAvailable`
// in lib/features/notifications/push_service.dart and the README.
//
// Nothing here has ever run against real Firestore, so the first deploy is
// where per-caregiver intervals and `lastNotifiedByUid` get their first real
// exercise. Watch for duplicate or missing pushes.

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

/**
 * How many recent feeds to scan when looking for the last one that resets the
 * clock. Only the most recent full milk feed matters, but a run of snacks or
 * solids can sit on top of it.
 */
const FETCH = 20;


/** Firestore `in` queries cap out at 10 values. */
const IN_QUERY_LIMIT = 10;

const MS_PER_MINUTE = 60_000;
const MINUTES_PER_DAY = 24 * 60;

/**
 * A caregiver's notification preferences (KAN-167), stored at
 * `notificationPrefs/{uid}`. Mirrors `lib/data/models/notification_prefs.dart`
 * — keep the two in step.
 */
interface NotificationPrefs {
  enabled: boolean;
  quietHoursEnabled: boolean;
  quietStartMinutes: number;
  quietEndMinutes: number;
  timezoneOffsetMinutes: number;
  overdueThresholdMinutes: number;
  reminderIntervalMinutes: number;
  remindersOff: boolean;
}

const DEFAULT_PREFS: NotificationPrefs = {
  enabled: true,
  quietHoursEnabled: false,
  quietStartMinutes: 22 * 60,
  quietEndMinutes: 7 * 60,
  timezoneOffsetMinutes: 0,
  overdueThresholdMinutes: 0,
  reminderIntervalMinutes: 180,
  remindersOff: false,
};

function readPrefs(data: FirebaseFirestore.DocumentData | undefined): NotificationPrefs {
  if (!data) return DEFAULT_PREFS;
  return {
    enabled: data.enabled ?? DEFAULT_PREFS.enabled,
    quietHoursEnabled:
      data.quietHoursEnabled ?? DEFAULT_PREFS.quietHoursEnabled,
    quietStartMinutes:
      data.quietStartMinutes ?? DEFAULT_PREFS.quietStartMinutes,
    quietEndMinutes: data.quietEndMinutes ?? DEFAULT_PREFS.quietEndMinutes,
    timezoneOffsetMinutes:
      data.timezoneOffsetMinutes ?? DEFAULT_PREFS.timezoneOffsetMinutes,
    overdueThresholdMinutes:
      data.overdueThresholdMinutes ?? DEFAULT_PREFS.overdueThresholdMinutes,
    reminderIntervalMinutes:
      data.reminderIntervalMinutes ?? DEFAULT_PREFS.reminderIntervalMinutes,
    remindersOff: data.remindersOff ?? DEFAULT_PREFS.remindersOff,
  };
}

/**
 * Minutes past local midnight for a UTC instant, given the caregiver's stored
 * UTC offset. The function runs in UTC, so without the offset "10 PM" would
 * mean 10 PM UTC for everyone.
 */
export function localMinutesAt(nowMs: number, offsetMinutes: number): number {
  const shifted = nowMs + offsetMinutes * MS_PER_MINUTE;
  const minutes = Math.floor(shifted / MS_PER_MINUTE);
  return ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
}

/** Whether the caregiver's local time falls inside their quiet window. */
export function isQuietAt(
  prefs: NotificationPrefs,
  localMinutes: number,
): boolean {
  if (!prefs.quietHoursEnabled) return false;
  if (prefs.quietStartMinutes === prefs.quietEndMinutes) return false;
  if (prefs.quietStartMinutes < prefs.quietEndMinutes) {
    return (
      localMinutes >= prefs.quietStartMinutes &&
      localMinutes < prefs.quietEndMinutes
    );
  }
  // Wraps midnight (the usual case): quiet from the evening until morning.
  return (
    localMinutes >= prefs.quietStartMinutes ||
    localMinutes < prefs.quietEndMinutes
  );
}

/**
 * Scheduled feed reminder (KAN-156, preferences in KAN-167). Every 15 minutes,
 * for each baby, this takes the last feed that resets the clock and adds each
 * caregiver's own reminder interval — the same rule as the in-app card
 * (`fixedIntervalDue`) — then pushes anyone now overdue who hasn't already
 * been told about that feed.
 *
 * It used to derive its own due time from a rolling average of recent gaps,
 * duplicating the app's prediction engine. That engine is gone: one statistic
 * can't describe a rhythm that is 3-hourly by day and 6-hourly at night, and
 * keeping two implementations of it in step by hand was a standing hazard.
 *
 * A caregiver is skipped when they have turned reminders off, when their local
 * time falls inside their quiet hours, or when their personal grace period has
 * not elapsed yet.
 *
 * Deploy: requires the Blaze plan. `cd functions && npm i && npm run deploy`.
 */
export const feedReminder = onSchedule("every 15 minutes", async () => {
  const babies = await db.collection("babies").get();
  const now = Date.now();

  for (const babyDoc of babies.docs) {
    const baby = babyDoc.data();
    try {
      const feedsSnap = await babyDoc.ref
        .collection("feedings")
        .orderBy("startTime", "desc")
        .limit(FETCH)
        .get();
      if (feedsSnap.empty) continue;

      // Snacks and solids don't reset the clock — a top-up isn't a feed's
      // worth of fuel, and solids supplement milk rather than replace it.
      // Mirrors `drivesFeedClock` in
      // lib/features/reminders/feed_prediction.dart, including the fallback to
      // the newest event when those are all that has been logged, so a
      // reminder still fires rather than going silent.
      // A missing `isSnack` means an event logged before the field existed.
      const milkFeeds = feedsSnap.docs.filter(
        (d) => d.get("isSnack") !== true && d.get("type") !== "solids",
      );
      const anchorDoc = milkFeeds[0] ?? feedsSnap.docs[0];
      const lastFedAt = (
        anchorDoc.get("startTime") as admin.firestore.Timestamp
      ).toMillis();

      const memberUids: string[] = baby.memberUids ?? [];
      if (memberUids.length === 0) continue;

      // Per-caregiver, because the interval is a per-caregiver setting: two
      // caregivers on the same baby can be due at different times.
      const notifiedByUid: Record<string, string> =
        baby.lastNotifiedByUid ?? {};
      // Pre-dates per-caregiver tracking; treat it as everyone's last, so a
      // deploy doesn't re-notify for a feed already covered.
      const legacyNotified: string | undefined = baby.lastNotifiedFeedId;

      // Keep only caregivers who want this notification now.
      const prefsDocs = await db.getAll(
        ...memberUids.map((uid) => db.collection("notificationPrefs").doc(uid)),
      );
      const wanted = memberUids.filter((uid, i) => {
        const prefs = readPrefs(prefsDocs[i]?.data());
        if (!prefs.enabled || prefs.remindersOff) return false;
        if ((notifiedByUid[uid] ?? legacyNotified) === anchorDoc.id) {
          return false;
        }
        const due = lastFedAt + prefs.reminderIntervalMinutes * MS_PER_MINUTE;
        if (now < due + prefs.overdueThresholdMinutes * MS_PER_MINUTE) {
          return false;
        }
        return !isQuietAt(prefs, localMinutesAt(now, prefs.timezoneOffsetMinutes));
      });
      if (wanted.length === 0) continue;

      const tokensSnap = await db
        .collection("fcmTokens")
        .where("uid", "in", wanted.slice(0, IN_QUERY_LIMIT))
        .get();
      const tokens = tokensSnap.docs.map((d) => d.id);
      if (tokens.length === 0) continue;

      const res = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: `${baby.name ?? "Baby"} may be due for a feed`,
          body: "It's been a while since the last full feed.",
        },
      });
      // Prune tokens FCM reports as no longer valid.
      const stale: Promise<unknown>[] = [];
      res.responses.forEach((r, i) => {
        if (
          !r.success &&
          r.error?.code === "messaging/registration-token-not-registered"
        ) {
          stale.push(tokensSnap.docs[i].ref.delete());
        }
      });
      await Promise.all(stale);

      // Only mark the feed as notified once something actually went out —
      // otherwise a caregiver silenced by quiet hours would never be told
      // about this feed after their quiet window ends. Marked per caregiver,
      // so one whose longer interval isn't up yet still gets told later.
      const reached = new Set(
        tokensSnap.docs.map((d) => d.get("uid") as string),
      );
      if (reached.size > 0) {
        const marks: Record<string, string> = {};
        for (const uid of reached) {
          marks[`lastNotifiedByUid.${uid}`] = anchorDoc.id;
        }
        await babyDoc.ref.update(marks);
      }
    } catch (err) {
      logger.error(`feedReminder failed for baby ${babyDoc.id}`, err);
    }
  }
});
