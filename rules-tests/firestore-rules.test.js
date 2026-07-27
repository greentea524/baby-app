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
  });
});

const asAlice = () => testEnv.authenticatedContext("alice").firestore();
const asMallory = () => testEnv.authenticatedContext("mallory").firestore();
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
