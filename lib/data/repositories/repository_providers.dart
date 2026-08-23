import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
// sharedPreferencesProvider lives with the theme provider (both are prefs-backed).
import '../../core/theme/theme_mode_provider.dart';
import '../models/baby.dart';
import '../models/caregiver_invite.dart';
import '../models/diaper_event.dart';
import '../models/feeding_event.dart';
import '../models/appointment.dart';
import '../models/growth_measurement.dart';
import '../models/notification_prefs.dart';
import '../models/pumping_event.dart';
import 'appointments_repository.dart';
import 'babies_repository.dart';
import 'diaper_repository.dart';
import 'feeding_repository.dart';
import 'growth_repository.dart';
import 'notification_prefs_repository.dart';
import 'pumping_repository.dart';

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// Null until a user is signed in. Downstream providers guard on this so
/// no query ever runs without an authenticated, scoped uid.
final babiesRepositoryProvider = Provider<BabiesRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return BabiesRepository(ref.watch(firestoreProvider), user.uid);
});

final babiesStreamProvider = StreamProvider<List<Baby>>((ref) {
  final repo = ref.watch(babiesRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchBabies();
});

const _selectedBabyKey = 'selected_baby_id';

/// The user's chosen baby, persisted across sessions (KAN-135). Null means
/// "no explicit choice yet" — [currentBabyProvider] then falls back to the
/// first baby.
final selectedBabyIdProvider = NotifierProvider<SelectedBabyNotifier, String?>(
  SelectedBabyNotifier.new,
);

class SelectedBabyNotifier extends Notifier<String?> {
  @override
  String? build() =>
      ref.read(sharedPreferencesProvider).getString(_selectedBabyKey);

  Future<void> select(String id) async {
    state = id;
    await ref.read(sharedPreferencesProvider).setString(_selectedBabyKey, id);
  }
}

/// The baby currently being logged against: the selected one if it still
/// exists, otherwise the first baby (or null when there are none). Every
/// per-baby repository scopes to this, so switching re-points all data.
final currentBabyProvider = Provider<Baby?>((ref) {
  final babies = ref.watch(babiesStreamProvider).value ?? const [];
  if (babies.isEmpty) return null;
  final selectedId = ref.watch(selectedBabyIdProvider);
  return babies.firstWhere(
    (b) => b.id == selectedId,
    orElse: () => babies.first,
  );
});

/// Feeding repository scoped to the current uid + current baby. Null when
/// signed out or no baby exists yet, so UI can guard cleanly.
final feedingRepositoryProvider = Provider<FeedingRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  final baby = ref.watch(currentBabyProvider);
  if (user == null || baby == null) return null;
  return FeedingRepository(ref.watch(firestoreProvider), baby.id, user.uid);
});

final recentFeedingsProvider = StreamProvider<List<FeedingEvent>>((ref) {
  final repo = ref.watch(feedingRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchRecent();
});

/// The most recent feeding of any kind, or null.
final lastFeedingProvider = Provider<FeedingEvent?>((ref) {
  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  return feeds.isEmpty ? null : feeds.first;
});

/// The most recent milk feed — breast or bottle — or null.
///
/// Powers the home "Last fed" row, which sits next to the next-feed
/// countdown. Solids are excluded so the two halves of that row answer the
/// same question: a purée at 5pm shouldn't headline a row whose countdown is
/// measured from the 3pm bottle.
final lastMilkFeedProvider = Provider<FeedingEvent?>((ref) {
  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  for (final f in feeds) {
    if (f.type != FeedingType.solids) return f;
  }
  return null;
});

/// The most recent feed that resets the milk clock, or null.
///
/// Narrower than [lastMilkFeedProvider], which counts snacks. Anything keying
/// off "a feed just happened" wants this one: a top-up does not move the
/// next-feed time, so treating it as a new feed makes whatever is watching
/// react to a clock that never moved.
final lastClockFeedProvider = Provider<FeedingEvent?>((ref) {
  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  for (final f in feeds) {
    if (f.drivesFeedClock) return f;
  }
  return null;
});

/// The most recent solids, or null when none have been logged. Powers the
/// home "Last ate" row, which has no prediction attached.
final lastSolidsProvider = Provider<FeedingEvent?>((ref) {
  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  for (final f in feeds) {
    if (f.type == FeedingType.solids) return f;
  }
  return null;
});

/// Diaper repository scoped to the current uid + current baby.
final diaperRepositoryProvider = Provider<DiaperRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  final baby = ref.watch(currentBabyProvider);
  if (user == null || baby == null) return null;
  return DiaperRepository(ref.watch(firestoreProvider), baby.id, user.uid);
});

final recentDiapersProvider = StreamProvider<List<DiaperEvent>>((ref) {
  final repo = ref.watch(diaperRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchRecent();
});

/// The most recent diaper change, or null. Powers the "last changed" card.
final lastDiaperProvider = Provider<DiaperEvent?>((ref) {
  final diapers = ref.watch(recentDiapersProvider).value ?? const [];
  return diapers.isEmpty ? null : diapers.first;
});

// --- Timeline (KAN-132): per-day queries -----------------------------------

/// The calendar day the timeline is viewing, normalised to local midnight.
/// Defaults to today.
final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DateTime>(
  SelectedDayNotifier.new,
);

class SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void setDay(DateTime day) => state = DateTime(day.year, day.month, day.day);

  void shift(int days) => state = state.add(Duration(days: days));
}

final feedingsForDayProvider = StreamProvider<List<FeedingEvent>>((ref) {
  final repo = ref.watch(feedingRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchForDay(ref.watch(selectedDayProvider));
});

final diapersForDayProvider = StreamProvider<List<DiaperEvent>>((ref) {
  final repo = ref.watch(diaperRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchForDay(ref.watch(selectedDayProvider));
});

// --- Pumping (KAN-145) -----------------------------------------------------

final pumpingRepositoryProvider = Provider<PumpingRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  final baby = ref.watch(currentBabyProvider);
  if (user == null || baby == null) return null;
  return PumpingRepository(ref.watch(firestoreProvider), baby.id, user.uid);
});

final recentPumpingProvider = StreamProvider<List<PumpingEvent>>((ref) {
  final repo = ref.watch(pumpingRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchRecent();
});

final pumpingForDayProvider = StreamProvider<List<PumpingEvent>>((ref) {
  final repo = ref.watch(pumpingRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchForDay(ref.watch(selectedDayProvider));
});

// --- Growth (KAN-136) ------------------------------------------------------

final growthRepositoryProvider = Provider<GrowthRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  final baby = ref.watch(currentBabyProvider);
  if (user == null || baby == null) return null;
  return GrowthRepository(ref.watch(firestoreProvider), baby.id, user.uid);
});

final growthMeasurementsProvider = StreamProvider<List<GrowthMeasurement>>((
  ref,
) {
  final repo = ref.watch(growthRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchAll();
});

// --- Appointments (KAN-176) ------------------------------------------------

final appointmentsRepositoryProvider = Provider<AppointmentsRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  final baby = ref.watch(currentBabyProvider);
  if (user == null || baby == null) return null;
  return AppointmentsRepository(
    ref.watch(firestoreProvider),
    baby.id,
    user.uid,
  );
});

/// Every appointment in date order. The screen splits it around "now" so the
/// boundary stays live while the app is open.
final appointmentsProvider = StreamProvider<List<Appointment>>((ref) {
  final repo = ref.watch(appointmentsRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchAll();
});

// --- Notification preferences (KAN-167) ------------------------------------

/// Scoped to the signed-in user; preferences follow the caregiver, not the
/// baby.
final notificationPrefsRepositoryProvider =
    Provider<NotificationPrefsRepository?>((ref) {
      final user = ref.watch(authStateProvider).value;
      if (user == null) return null;
      return NotificationPrefsRepository(
        ref.watch(firestoreProvider),
        user.uid,
      );
    });

/// Falls back to defaults while loading or when signed out, so the settings
/// UI always has something sensible to render.
final notificationPrefsProvider = StreamProvider<NotificationPrefs>((ref) {
  final repo = ref.watch(notificationPrefsRepositoryProvider);
  if (repo == null) return Stream.value(const NotificationPrefs());
  return repo.watch();
});

/// Whether [notificationPrefsProvider] is carrying the account's stored values
/// rather than the signed-out defaults.
///
/// The two are indistinguishable from the outside — a caregiver who has never
/// saved anything and a caregiver who is signed out both produce a default
/// [NotificationPrefs] — so anything that treats the stream as the account
/// speaking has to ask this first. Without it, signing out would look like the
/// account asking for a 3-hour interval (#27).
final hasAccountPrefsProvider = Provider<bool>(
  (ref) => ref.watch(notificationPrefsRepositoryProvider) != null,
);

// --- Multi-caregiver (KAN-134) ---------------------------------------------

/// Caregivers already on the current baby (from its members map).
final currentBabyMembersProvider = Provider<Map<String, CaregiverRole>>((ref) {
  return ref.watch(currentBabyProvider)?.members ?? const {};
});

/// Pending invites on the current baby (owner/editor management view).
final currentBabyInvitesProvider = StreamProvider<List<CaregiverInvite>>((ref) {
  final repo = ref.watch(babiesRepositoryProvider);
  final baby = ref.watch(currentBabyProvider);
  if (repo == null || baby == null) return Stream.value(const []);
  return repo.watchInvitesForBaby(baby.id);
});

/// Whether the signed-in address may start a household of its own.
///
/// The app is private. Anyone can sign in with Google — rules cannot prevent
/// that — but without an entry in `allowedUsers` they can neither read a baby
/// they are not a member of nor create one, so signing in gets them a locked
/// door rather than a free tracker on someone else's bill.
///
/// Lowercased to match the rules, which compare against
/// `request.auth.token.email.lower()`. If the two normalised differently, the
/// app would offer a household that the rules then refused to create.
///
/// Loading while it is still being fetched, so the UI can wait rather than
/// accusing someone of not being invited during a round trip.
final mayStartHouseholdProvider = FutureProvider<bool>((ref) async {
  final email = ref.watch(authStateProvider).value?.email;
  if (email == null) return false;
  final doc = await ref
      .watch(firestoreProvider)
      .collection('allowedUsers')
      .doc(email.trim().toLowerCase())
      .get();
  return doc.exists;
});

/// Invitations addressed to the signed-in user, across all babies. Powers
/// the "you've been invited" acceptance prompt.
final incomingInvitesProvider = StreamProvider<List<CaregiverInvite>>((ref) {
  final repo = ref.watch(babiesRepositoryProvider);
  final email = ref.watch(authStateProvider).value?.email;
  if (repo == null || email == null) return Stream.value(const []);
  return repo.watchIncomingInvites(email);
});
