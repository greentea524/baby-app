import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
// sharedPreferencesProvider lives with the theme provider (both are prefs-backed).
import '../../core/theme/theme_mode_provider.dart';
import '../models/baby.dart';
import '../models/caregiver_invite.dart';
import '../models/diaper_event.dart';
import '../models/feeding_event.dart';
import '../models/growth_measurement.dart';
import 'babies_repository.dart';
import 'diaper_repository.dart';
import 'feeding_repository.dart';
import 'growth_repository.dart';

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

/// The most recent feeding, or null. Powers the home "last fed" indicator.
final lastFeedingProvider = Provider<FeedingEvent?>((ref) {
  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  return feeds.isEmpty ? null : feeds.first;
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

/// Invitations addressed to the signed-in user, across all babies. Powers
/// the "you've been invited" acceptance prompt.
final incomingInvitesProvider = StreamProvider<List<CaregiverInvite>>((ref) {
  final repo = ref.watch(babiesRepositoryProvider);
  final email = ref.watch(authStateProvider).value?.email;
  if (repo == null || email == null) return Stream.value(const []);
  return repo.watchIncomingInvites(email);
});
