import { after, before, beforeEach, describe, it } from "node:test";
import { readFileSync } from "node:fs";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
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
    await setDoc(doc(db, "babies", BABY, "feedings", "f1"), {
      type: "bottle",
      amountMl: 120,
    });
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
  it("lets a member read and write feedings", async () => {
    const db = asAlice();
    await assertSucceeds(getDoc(doc(db, "babies", BABY, "feedings", "f1")));
    await assertSucceeds(
      setDoc(doc(db, "babies", BABY, "feedings", "f2"), { type: "breast" }),
    );
  });

  it("blocks a non-member from reading feedings", async () => {
    await assertFails(
      getDoc(doc(asMallory(), "babies", BABY, "feedings", "f1")),
    );
  });

  it("blocks a non-member from writing growth measurements", async () => {
    await assertFails(
      setDoc(doc(asMallory(), "babies", BABY, "growth", "g1"), {
        weightKg: 7.5,
      }),
    );
  });

  it("blocks an invitee who has not joined yet", async () => {
    // Holding an invite is not membership until it is accepted.
    await assertFails(getDoc(doc(asBob(), "babies", BABY, "feedings", "f1")));
  });

  it("gates a newly added subcollection without a rules change", async () => {
    // The wildcard `match /{sub}/{docId}` is what lets features like
    // appointments ship without touching firestore.rules. Pin that down so a
    // future narrowing of the wildcard fails loudly here.
    await assertSucceeds(
      setDoc(doc(asAlice(), "babies", BABY, "appointments", "ap1"), {
        kind: "checkup",
      }),
    );
    await assertFails(
      setDoc(doc(asMallory(), "babies", BABY, "appointments", "ap2"), {
        kind: "checkup",
      }),
    );
    await assertFails(
      getDoc(doc(asMallory(), "babies", BABY, "appointments", "ap1")),
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
