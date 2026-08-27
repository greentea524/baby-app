import { after, before, beforeEach, describe, it } from "node:test";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

// Access control lives entirely in firestore.rules, so a regression here
// leaks one family's logs to another. These tests run the real rules against
// the Firestore emulator.
//
// Fixture: `alice` owns baby1; `bob` is invited but has not joined; `mallory`
// has no relationship to it.
const BABY = "baby1";
const BOB_EMAIL = "bob@example.com";
const ALICE_EMAIL = "alice@example.com";
// Signed in, never invited, not on the allowlist.
const MALLORY_EMAIL = "mallory@example.com";

let testEnv;

function babyDoc(db, babyId = BABY) {
  return doc(db, "babies", babyId);
}

// --- What the app actually writes ------------------------------------------
//
// These mirror each model's `toMap()` plus the stamps its repository adds,
// right down to the explicit nulls — `toMap` writes every optional field, so
// "absent" and "null" are different things to the rules and both have to
// pass. If a model gains a field, the builder here should gain it too, or
// these stop being evidence that the real client still works.
const AT = Timestamp.fromDate(new Date("2026-08-13T09:00:00Z"));

const stamped = (uid = "alice") => ({
  createdBy: uid,
  createdAt: serverTimestamp(),
});

const edited = (uid = "alice") => ({
  updatedBy: uid,
  updatedAt: serverTimestamp(),
});

const feeding = (over = {}) => ({
  type: "bottle",
  startTime: AT,
  durationMinutes: null,
  amountMl: 120,
  side: null,
  notes: null,
  isSnack: false,
  ...stamped(),
  ...over,
});

const diaper = (over = {}) => ({
  type: "dirty",
  time: AT,
  notes: null,
  poopSize: "small",
  ...stamped(),
  ...over,
});

const growth = (over = {}) => ({
  date: AT,
  weightKg: 7.5,
  heightCm: null,
  headCm: null,
  ...stamped(),
  ...over,
});

const pump = (over = {}) => ({
  time: AT,
  durationMinutes: 15,
  amountMl: 90,
  side: "both",
  notes: null,
  ...stamped(),
  ...over,
});

const appointment = (over = {}) => ({
  at: AT,
  kind: "checkup",
  title: "6-month well visit",
  provider: null,
  location: null,
  notes: null,
  completedAt: null,
  ...stamped(),
  ...over,
});

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-baby-app",
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  // Seed with rules disabled so the fixture itself isn't under test.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(babyDoc(db), {
      name: "Ada",
      ownerUid: "alice",
      memberUids: ["alice"],
      members: { alice: "owner" },
    });
    await setDoc(doc(db, "babies", BABY, "invites", BOB_EMAIL), {
      email: BOB_EMAIL,
      role: "editor",
      invitedByUid: "alice",
    });
    await setDoc(doc(db, "babies", BABY, "feedings", "f1"), feeding());
    // The app is invite-only: starting a household needs an entry here.
    await setDoc(doc(db, "allowedUsers", ALICE_EMAIL), { note: "owner" });
  });
});

const asAlice = () =>
  testEnv.authenticatedContext("alice", { email: ALICE_EMAIL }).firestore();
const asMallory = () =>
  testEnv.authenticatedContext("mallory", { email: MALLORY_EMAIL }).firestore();
const asBob = () =>
  testEnv.authenticatedContext("bob", { email: BOB_EMAIL }).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

describe("baby profile access", () => {
  it("lets a member read the baby", async () => {
    await assertSucceeds(getDoc(babyDoc(asAlice())));
  });

  it("blocks a non-member from reading the baby", async () => {
    await assertFails(getDoc(babyDoc(asMallory())));
  });

  it("blocks an unauthenticated read", async () => {
    await assertFails(getDoc(babyDoc(asAnon())));
  });

  it("lets a member update the baby", async () => {
    await assertSucceeds(updateDoc(babyDoc(asAlice()), { name: "Ada B" }));
  });

  it("blocks a non-member from updating the baby", async () => {
    await assertFails(updateDoc(babyDoc(asMallory()), { name: "pwned" }));
  });
});

describe("baby creation", () => {
  it("allows creating a baby you solely own", async () => {
    await assertSucceeds(
      setDoc(babyDoc(asAlice(), "new1"), {
        name: "New",
        ownerUid: "alice",
        memberUids: ["alice"],
        members: { alice: "owner" },
      }),
    );
  });

  it("blocks creating a baby owned by someone else", async () => {
    await assertFails(
      setDoc(babyDoc(asMallory(), "new2"), {
        name: "Sneaky",
        ownerUid: "alice",
        memberUids: ["alice"],
        members: { alice: "owner" },
      }),
    );
  });

  it("blocks smuggling extra members in at creation", async () => {
    await assertFails(
      setDoc(babyDoc(asMallory(), "new3"), {
        name: "Sneaky",
        ownerUid: "mallory",
        memberUids: ["mallory", "alice"],
        members: { mallory: "owner", alice: "editor" },
      }),
    );
  });
});

describe("the allowlist", () => {
  it("blocks a signed-in stranger from starting a household", async () => {
    // Everything about this document is correct — sole owner, own uid. The
    // only thing wrong with it is who is asking, which is the whole point:
    // without this, anyone with a Google account gets a free baby tracker on
    // someone else's Firebase bill.
    await assertFails(
      setDoc(babyDoc(asMallory(), "new4"), {
        name: "Uninvited",
        ownerUid: "mallory",
        memberUids: ["mallory"],
        members: { mallory: "owner" },
      }),
    );
  });

  it("lets an allowed caregiver start one", async () => {
    await assertSucceeds(
      setDoc(babyDoc(asAlice(), "new5"), {
        name: "Second",
        ownerUid: "alice",
        memberUids: ["alice"],
        members: { alice: "owner" },
      }),
    );
  });

  it("does not stand between an invitee and their invite", async () => {
    // Bob is invited but not allowlisted, and must stay able to accept. The
    // allowlist gates starting a household, not joining one — if it gated
    // both, it would lock out exactly the people it was meant to let in.
    await assertSucceeds(
      updateDoc(babyDoc(asBob()), {
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      }),
    );
  });

  it("lets you check your own entry", async () => {
    await assertSucceeds(getDoc(doc(asAlice(), "allowedUsers", ALICE_EMAIL)));
  });

  it("blocks reading somebody else's", async () => {
    // Otherwise any account could enumerate who has access.
    await assertFails(getDoc(doc(asMallory(), "allowedUsers", ALICE_EMAIL)));
  });

  it("blocks writing yourself in", async () => {
    await assertFails(
      setDoc(doc(asMallory(), "allowedUsers", MALLORY_EMAIL), { note: "hi" }),
    );
  });

  it("matches the address whatever case the token carries", async () => {
    // Providers are not obliged to normalise case, and a document id is
    // matched byte for byte. Without lowercasing, the same person would be
    // allowed or refused depending on how their token happened to spell them.
    const shouting = testEnv
      .authenticatedContext("alice", { email: "Alice@Example.COM" })
      .firestore();
    await assertSucceeds(getDoc(doc(shouting, "allowedUsers", ALICE_EMAIL)));
    await assertSucceeds(
      setDoc(babyDoc(shouting, "new6"), {
        name: "Third",
        ownerUid: "alice",
        memberUids: ["alice"],
        members: { alice: "owner" },
      }),
    );
  });
});

describe("baby deletion", () => {
  it("lets the owner delete the profile", async () => {
    await assertSucceeds(deleteDoc(babyDoc(asAlice())));
  });

  it("blocks a non-owner member from deleting the profile", async () => {
    // Promote bob to a full member first — membership alone must not grant
    // deletion.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(babyDoc(ctx.firestore()), {
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      });
    });
    await assertFails(deleteDoc(babyDoc(asBob())));
  });
});

describe("event subcollections", () => {
  const at = (db, sub, id) => doc(db, "babies", BABY, sub, id);

  it("blocks a non-member from reading feedings", async () => {
    await assertFails(getDoc(at(asMallory(), "feedings", "f1")));
  });

  it("blocks a non-member from writing growth measurements", async () => {
    await assertFails(setDoc(at(asMallory(), "growth", "g1"), growth()));
  });

  it("blocks an invitee who has not joined yet", async () => {
    // Holding an invite is not membership until it is accepted.
    await assertFails(getDoc(at(asBob(), "feedings", "f1")));
  });

  it("blocks a subcollection the app does not have", async () => {
    // Was allowed by the old `match /{sub}/{docId}` wildcard: a member could
    // create any collection they liked under a baby, and nothing in the app
    // would ever read it. Storage nobody is watching is storage nobody
    // notices filling up.
    await assertFails(
      setDoc(at(asAlice(), "scratch", "x1"), { anything: true }),
    );
  });
});

// The half that matters most. Validation that rejects a real entry is worse
// than no validation at all: the write is already in the local cache and
// looks saved, and the rejection surfaces whenever the device next reaches
// the server. Every payload here mirrors what the repositories send.
describe("what the app writes today", () => {
  const cases = {
    feedings: feeding,
    diapers: diaper,
    growth: growth,
    pumps: pump,
    appointments: appointment,
  };

  for (const [sub, build] of Object.entries(cases)) {
    it(`accepts a ${sub} entry as the app sends it`, async () => {
      await assertSucceeds(
        setDoc(doc(asAlice(), "babies", BABY, sub, "new1"), build()),
      );
    });

    it(`accepts an edit to a ${sub} entry`, async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "babies", BABY, sub, "e1"), build());
      });
      await assertSucceeds(
        updateDoc(doc(asAlice(), "babies", BABY, sub, "e1"), {
          ...build(),
          ...edited(),
        }),
      );
    });
  }

  it("accepts the optional fields left empty, as a quick log does", async () => {
    // The fast path through every sheet: a type, a time, and nothing else.
    await assertSucceeds(
      setDoc(
        doc(asAlice(), "babies", BABY, "feedings", "quick"),
        feeding({
          amountMl: null,
          durationMinutes: null,
          side: null,
          notes: null,
        }),
      ),
    );
  });

  it("accepts a breast feed with a duration and a side", async () => {
    await assertSucceeds(
      setDoc(
        doc(asAlice(), "babies", BABY, "feedings", "breast"),
        feeding({
          type: "breast",
          amountMl: null,
          durationMinutes: 12,
          side: "left",
          isSnack: true,
        }),
      ),
    );
  });

  it("accepts a field the rules have never heard of", async () => {
    // Deliberate: being strict about unknown fields means every new field is
    // a rules deploy before the app can ship it, and rules deploys are a
    // manual step here. A schema that can move is worth more than that.
    await assertSucceeds(
      setDoc(
        doc(asAlice(), "babies", BABY, "feedings", "future"),
        feeding({ nursedInPublic: true }),
      ),
    );
  });
});

describe("attribution", () => {
  it("blocks logging an entry under someone else's name", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(babyDoc(ctx.firestore()), {
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      });
    });
    await assertFails(
      setDoc(
        doc(asBob(), "babies", BABY, "feedings", "forged"),
        feeding({ createdBy: "alice" }),
      ),
    );
  });

  it("blocks rewriting who created an entry", async () => {
    await assertFails(
      updateDoc(doc(asAlice(), "babies", BABY, "feedings", "f1"), {
        createdBy: "mallory",
        ...edited(),
      }),
    );
  });

  it("blocks an edit that does not say who made it", async () => {
    await assertFails(
      updateDoc(doc(asAlice(), "babies", BABY, "feedings", "f1"), {
        amountMl: 200,
      }),
    );
  });

  it("blocks an edit signed as somebody else", async () => {
    await assertFails(
      updateDoc(doc(asAlice(), "babies", BABY, "feedings", "f1"), {
        amountMl: 200,
        ...edited("bob"),
      }),
    );
  });
});

describe("malformed entries", () => {
  const rejected = {
    "a time that is a string": feeding({ startTime: "2026-08-13T09:00:00Z" }),
    "a time that is a number": feeding({ startTime: 1786000000 }),
    "a negative amount": feeding({ amountMl: -120 }),
    "an amount that is an object": feeding({ amountMl: { ml: 120 } }),
    "a duration with a fraction": feeding({ durationMinutes: 12.5 }),
    "a negative duration": feeding({ durationMinutes: -5 }),
    "a feed type nobody defined": feeding({ type: "telepathy" }),
    "a side nobody defined": feeding({ side: "middle" }),
    "isSnack as a string": feeding({ isSnack: "yes" }),
    "notes longer than anything a person types": feeding({
      notes: "x".repeat(1001),
    }),
  };

  for (const [what, payload] of Object.entries(rejected)) {
    it(`rejects ${what}`, async () => {
      await assertFails(
        setDoc(doc(asAlice(), "babies", BABY, "feedings", "bad"), payload),
      );
    });
  }

  it("rejects a diaper size nobody defined", async () => {
    await assertFails(
      setDoc(
        doc(asAlice(), "babies", BABY, "diapers", "bad"),
        diaper({ poopSize: "enormous" }),
      ),
    );
  });

  it("rejects a negative weight", async () => {
    await assertFails(
      setDoc(
        doc(asAlice(), "babies", BABY, "growth", "bad"),
        growth({ weightKg: -1 }),
      ),
    );
  });

  it("rejects an appointment kind nobody defined", async () => {
    await assertFails(
      setDoc(
        doc(asAlice(), "babies", BABY, "appointments", "bad"),
        appointment({ kind: "seance" }),
      ),
    );
  });

  it("rejects a malformed edit, not just a malformed create", async () => {
    await assertFails(
      updateDoc(doc(asAlice(), "babies", BABY, "feedings", "f1"), {
        amountMl: -1,
        ...edited(),
      }),
    );
  });

  it("still accepts notes right up to the cap", async () => {
    await assertSucceeds(
      setDoc(
        doc(asAlice(), "babies", BABY, "feedings", "long"),
        feeding({ notes: "x".repeat(1000) }),
      ),
    );
  });
});

describe("invite acceptance", () => {
  it("lets an invited user add exactly themselves", async () => {
    await assertSucceeds(
      updateDoc(babyDoc(asBob()), {
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      }),
    );
  });

  it("blocks a user with no matching invite", async () => {
    await assertFails(
      updateDoc(babyDoc(asMallory()), {
        memberUids: ["alice", "mallory"],
        members: { alice: "owner", mallory: "editor" },
      }),
    );
  });

  it("blocks an invitee from dropping the existing members", async () => {
    await assertFails(
      updateDoc(babyDoc(asBob()), {
        memberUids: ["bob"],
        members: { bob: "owner" },
      }),
    );
  });

  it("blocks an invitee from seizing ownership", async () => {
    await assertFails(
      updateDoc(babyDoc(asBob()), {
        ownerUid: "bob",
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      }),
    );
  });

  it("lets the invitee read their own invite", async () => {
    await assertSucceeds(
      getDoc(doc(asBob(), "babies", BABY, "invites", BOB_EMAIL)),
    );
  });

  it("blocks an unrelated user from reading someone else's invite", async () => {
    await assertFails(
      getDoc(doc(asMallory(), "babies", BABY, "invites", BOB_EMAIL)),
    );
  });
});

describe("who may issue and revoke invites", () => {
  const CAROL_EMAIL = "carol@example.com";

  /** Adds bob as an ordinary (non-owner) member, bypassing rules. */
  async function addBobAsMember() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(babyDoc(ctx.firestore()), {
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      });
    });
  }

  const inviteRef = (db, email) => doc(db, "babies", BABY, "invites", email);

  const newInvite = (email) => ({
    email,
    role: "editor",
    invitedByUid: "alice",
  });

  it("lets the owner invite someone", async () => {
    await assertSucceeds(
      setDoc(inviteRef(asAlice(), CAROL_EMAIL), newInvite(CAROL_EMAIL)),
    );
  });

  it("blocks a caregiver from inviting anyone", async () => {
    // Growing the roster is the same authority the update rules withhold from
    // a caregiver; letting them do it via an invite would route around that.
    await addBobAsMember();
    await assertFails(
      setDoc(inviteRef(asBob(), CAROL_EMAIL), newInvite(CAROL_EMAIL)),
    );
  });

  it("blocks a stranger from inviting anyone", async () => {
    await assertFails(
      setDoc(inviteRef(asMallory(), CAROL_EMAIL), newInvite(CAROL_EMAIL)),
    );
  });

  it("lets the owner revoke an invite", async () => {
    await assertSucceeds(deleteDoc(inviteRef(asAlice(), BOB_EMAIL)));
  });

  it("blocks a caregiver from revoking someone else's invite", async () => {
    await addBobAsMember();
    // Bob is a member here, but carol's invite is not his to revoke — so the
    // invitee escape hatch does not cover him either.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        inviteRef(ctx.firestore(), CAROL_EMAIL),
        newInvite(CAROL_EMAIL),
      );
    });
    await assertFails(deleteDoc(inviteRef(asBob(), CAROL_EMAIL)));
  });

  it("still lets the invitee delete their own on accept or decline", async () => {
    // acceptInvite and declineInvite both delete the invite as the invitee,
    // so tightening the member path must not close this one.
    await assertSucceeds(deleteDoc(inviteRef(asBob(), BOB_EMAIL)));
  });

  it("still lets a caregiver see pending invites", async () => {
    // The Caregivers screen lists them for every member; only the actions are
    // owner-only.
    await addBobAsMember();
    await assertSucceeds(getDoc(inviteRef(asBob(), BOB_EMAIL)));
  });
});

describe("membership changes", () => {
  /** Promotes bob to a full member, bypassing rules. */
  async function makeBobAMember() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(babyDoc(ctx.firestore()), {
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      });
    });
  }

  it("lets any member edit the profile fields", async () => {
    await makeBobAMember();
    await assertSucceeds(updateDoc(babyDoc(asBob()), { name: "Ada B" }));
  });

  it("lets the owner remove a caregiver", async () => {
    await makeBobAMember();
    await assertSucceeds(
      updateDoc(babyDoc(asAlice()), {
        memberUids: ["alice"],
        members: { alice: "owner" },
      }),
    );
  });

  it("lets a caregiver remove themselves", async () => {
    await makeBobAMember();
    await assertSucceeds(
      updateDoc(babyDoc(asBob()), {
        memberUids: ["alice"],
        members: { alice: "owner" },
      }),
    );
  });

  it("blocks a caregiver from removing someone else", async () => {
    // carol and bob are both editors; neither may evict the other.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(babyDoc(ctx.firestore()), {
        memberUids: ["alice", "bob", "carol"],
        members: { alice: "owner", bob: "editor", carol: "editor" },
      });
    });
    await assertFails(
      updateDoc(babyDoc(asBob()), {
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      }),
    );
  });

  it("blocks a caregiver from removing the owner", async () => {
    await makeBobAMember();
    await assertFails(
      updateDoc(babyDoc(asBob()), {
        memberUids: ["bob"],
        members: { bob: "editor" },
      }),
    );
  });

  it("blocks a caregiver from seizing ownership", async () => {
    // The worst case: an editor rewrites ownerUid to themselves, which would
    // also hand them the owner-only delete.
    await makeBobAMember();
    await assertFails(updateDoc(babyDoc(asBob()), { ownerUid: "bob" }));
  });

  it("blocks the owner from handing ownership to someone else", async () => {
    await makeBobAMember();
    await assertFails(updateDoc(babyDoc(asAlice()), { ownerUid: "bob" }));
  });
});

describe("fcm tokens", () => {
  it("lets a user register a token under their own uid", async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), "fcmTokens", "token-a"), { uid: "alice" }),
    );
  });

  it("blocks registering a token under someone else's uid", async () => {
    await assertFails(
      setDoc(doc(asMallory(), "fcmTokens", "token-b"), { uid: "alice" }),
    );
  });

  it("blocks reading another user's token", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "fcmTokens", "token-a"), {
        uid: "alice",
      });
    });
    await assertFails(getDoc(doc(asMallory(), "fcmTokens", "token-a")));
    await assertSucceeds(getDoc(doc(asAlice(), "fcmTokens", "token-a")));
  });
});

// --- Deleting a baby and everything under it (#28) -------------------------
//
// Firestore does not delete subcollections with their parent, and every
// subcollection rule here reads the baby document to check membership. So the
// order is not a preference: parent-first strands the data behind rules that
// can no longer resolve, for good.
describe("deleting a baby's data", () => {
  const seed = async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "babies/del1"), {
        name: "Ada",
        ownerUid: "alice",
        memberUids: ["alice", "bob"],
        members: { alice: "owner", bob: "editor" },
      });
      await setDoc(doc(db, "babies/del1/feedings/f1"), {
        type: "bottle", startTime: new Date(), createdBy: "alice",
      });
      await setDoc(doc(db, "babies/del1/diapers/d1"), {
        type: "wet", time: new Date(), createdBy: "alice",
      });
      await setDoc(doc(db, "babies/del1/invites/x@y.com"), {
        email: "x@y.com", role: "editor", invitedByUid: "alice",
      });
    });
  };

  it("lets the owner clear the children while the baby still exists", async () => {
    await seed();
    const owner = asAlice();

    await assertSucceeds(deleteDoc(doc(owner, "babies/del1/feedings/f1")));
    await assertSucceeds(deleteDoc(doc(owner, "babies/del1/diapers/d1")));
    await assertSucceeds(deleteDoc(doc(owner, "babies/del1/invites/x@y.com")));
    await assertSucceeds(deleteDoc(doc(owner, "babies/del1")));

    // Nothing left anywhere, which is the whole claim.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const path of [
        "babies/del1",
        "babies/del1/feedings/f1",
        "babies/del1/diapers/d1",
        "babies/del1/invites/x@y.com",
      ]) {
        const snap = await getDoc(doc(db, path));
        assert.equal(snap.exists(), false, `${path} survived`);
      }
    });
  });

  it("strands the children if the baby goes first", async () => {
    // The bug this replaces, kept as a test because it is the reason the
    // order exists. Delete the parent and the feeding is still stored and no
    // longer reachable by anyone — not readable, not deletable, for good.
    await seed();
    const owner = asAlice();

    await assertSucceeds(deleteDoc(doc(owner, "babies/del1")));

    let survived = false;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      survived = (
        await getDoc(doc(ctx.firestore(), "babies/del1/feedings/f1"))
      ).exists();
    });
    assert.equal(survived, true, "the feeding should still be stored");

    await assertFails(getDoc(doc(owner, "babies/del1/feedings/f1")));
    await assertFails(deleteDoc(doc(owner, "babies/del1/feedings/f1")));
  });

  it("does not let a member delete the baby, only the owner", async () => {
    await seed();
    await assertFails(deleteDoc(doc(asBob(), "babies/del1")));
  });

  it("but a member may clear the entries, so the sweep is not owner-gated", async () => {
    await seed();
    await assertSucceeds(deleteDoc(doc(asBob(), "babies/del1/feedings/f1")));
  });
});

// --- Leaving the allowlist (#28) -------------------------------------------
//
// Deleting an account has to take the address with it, or the deletion keeps
// the one piece of it that identifies a person.
describe("removing your own allowlist entry", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "allowedUsers", ALICE_EMAIL), { note: "owner" });
      await setDoc(doc(db, "allowedUsers", BOB_EMAIL), { note: "invited" });
    });
  });

  it("lets you delete your own", async () => {
    await assertSucceeds(deleteDoc(doc(asAlice(), "allowedUsers", ALICE_EMAIL)));
  });

  it("does not let you delete anybody else's", async () => {
    // The whole risk in loosening this rule: the allowlist is what keeps the
    // app private, so one caregiver must not be able to evict another.
    await assertFails(deleteDoc(doc(asAlice(), "allowedUsers", BOB_EMAIL)));
    await assertFails(deleteDoc(doc(asMallory(), "allowedUsers", ALICE_EMAIL)));
  });

  it("matches the address case-insensitively, as the read does", async () => {
    const shouting = testEnv
      .authenticatedContext("alice", { email: "Alice@Example.COM" })
      .firestore();
    await assertSucceeds(deleteDoc(doc(shouting, "allowedUsers", ALICE_EMAIL)));
  });

  it("still refuses a signed-out caller", async () => {
    await assertFails(deleteDoc(doc(asAnon(), "allowedUsers", ALICE_EMAIL)));
  });

  it("does not open the door to writing one", async () => {
    // There is no create rule, so leaving is one-way: coming back means
    // someone adding the address again by hand.
    await assertFails(
      setDoc(doc(asAlice(), "allowedUsers", "newcomer@example.com"), {}),
    );
    await assertFails(setDoc(doc(asAlice(), "allowedUsers", ALICE_EMAIL), {}));
  });
});
