import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/caregiver_invite.dart';

/// What Home shows to a signed-in caregiver who has no baby yet.
///
/// Three different people land on the same empty screen — the owner opening
/// the app for the first time, someone who has been invited onto an existing
/// baby, and a stranger who found the URL — and each needs a different thing
/// said to them.
enum HomeEmptyState {
  /// Still finding out. Nothing is offered and nobody is turned away until
  /// the answer is in; a round trip is not grounds for an accusation.
  loading,

  /// May start a household of their own: the ordinary first-run prompt.
  addBaby,

  /// Cannot start one, but has been invited onto someone else's baby. The
  /// invite banner above is their way in, so the screen points at it rather
  /// than offering a button that the rules would refuse.
  awaitingInvite,

  /// Neither invited onto a baby nor allowed to start one.
  locked,
}

/// Decides which of the four empty states Home is in.
///
/// The allowlist is checked first: someone who may start a household gets the
/// plain prompt whether or not an invite is also waiting, because either
/// route works for them.
///
/// An *error* fetching the allowlist reads as [HomeEmptyState.addBaby], not
/// as [HomeEmptyState.locked]. A failed read means offline or a hiccup far
/// more often than it means uninvited, and the security rules — not this
/// screen — are what actually stop a create. Guessing "locked" here would
/// lock out the owner every time their connection dropped.
HomeEmptyState homeEmptyState({
  required AsyncValue<bool> mayStartHousehold,
  required AsyncValue<List<CaregiverInvite>> incomingInvites,
}) {
  if (mayStartHousehold.hasError) return HomeEmptyState.addBaby;
  if (mayStartHousehold.value == true) return HomeEmptyState.addBaby;
  if (incomingInvites.value?.isNotEmpty ?? false) {
    return HomeEmptyState.awaitingInvite;
  }
  if (mayStartHousehold.isLoading || incomingInvites.isLoading) {
    return HomeEmptyState.loading;
  }
  return HomeEmptyState.locked;
}
