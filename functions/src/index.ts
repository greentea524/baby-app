import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

/** How many recent feeds to average when predicting the next one. */
const WINDOW = 8;

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
}

const DEFAULT_PREFS: NotificationPrefs = {
  enabled: true,
  quietHoursEnabled: false,
  quietStartMinutes: 22 * 60,
  quietEndMinutes: 7 * 60,
  timezoneOffsetMinutes: 0,
  overdueThresholdMinutes: 0,
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
 * for each baby, this predicts the next feed from a rolling average of recent
 * intervals — the same logic as the in-app card (`predictNextFeed`) — and, if
 * a feed is now overdue and we haven't already notified for the latest feed,
 * pushes the caregivers who want to hear about it right now.
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
        .limit(WINDOW)
        .get();
      if (feedsSnap.size < 2) continue;

      // startTimes ascending (oldest -> newest).
      const times = feedsSnap.docs
        .map((d) => (d.get("startTime") as admin.firestore.Timestamp).toMillis())
        .reverse();

      let total = 0;
      for (let i = 1; i < times.length; i++) total += times[i] - times[i - 1];
      const avg = total / (times.length - 1);
      const due = times[times.length - 1] + avg;
      if (now < due) continue;

      // Don't re-notify for a feed we've already reminded about.
      const latestFeedId = feedsSnap.docs[0].id;
      if (baby.lastNotifiedFeedId === latestFeedId) continue;

      const memberUids: string[] = baby.memberUids ?? [];
      if (memberUids.length === 0) continue;

      // Keep only caregivers who want this notification now.
      const prefsDocs = await db.getAll(
        ...memberUids.map((uid) => db.collection("notificationPrefs").doc(uid)),
      );
      const wanted = memberUids.filter((_, i) => {
        const prefs = readPrefs(prefsDocs[i]?.data());
        if (!prefs.enabled) return false;
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
          body: "It's been longer than usual since the last feed.",
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
      // about this feed after their quiet window ends.
      await babyDoc.ref.update({ lastNotifiedFeedId: latestFeedId });
    } catch (err) {
      logger.error(`feedReminder failed for baby ${babyDoc.id}`, err);
    }
  }
});
