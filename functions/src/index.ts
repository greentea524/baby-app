import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

/** How many recent feeds to average when predicting the next one. */
const WINDOW = 8;

/**
 * Scheduled feed reminder (KAN-156). Every 15 minutes, for each baby, this
 * predicts the next feed from a rolling average of recent intervals — the
 * same logic as the in-app card (`predictNextFeed`) — and, if a feed is now
 * overdue and we haven't already notified for the latest feed, pushes every
 * caregiver's registered device.
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

      const memberUids: string[] = (baby.memberUids ?? []).slice(0, 10);
      if (memberUids.length === 0) continue;

      const tokensSnap = await db
        .collection("fcmTokens")
        .where("uid", "in", memberUids)
        .get();
      const tokens = tokensSnap.docs.map((d) => d.id);

      if (tokens.length > 0) {
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
      }

      await babyDoc.ref.update({ lastNotifiedFeedId: latestFeedId });
    } catch (err) {
      logger.error(`feedReminder failed for baby ${babyDoc.id}`, err);
    }
  }
});
