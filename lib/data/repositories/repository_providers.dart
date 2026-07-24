import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../models/baby.dart';
import '../models/diaper_event.dart';
import '../models/feeding_event.dart';
import 'babies_repository.dart';
import 'diaper_repository.dart';
import 'feeding_repository.dart';

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

/// The baby currently being logged against. Until the full profile-switching
/// UI lands (KAN-135), this simply follows the first baby on the account;
/// screens prompt the user to create one when the list is empty.
final currentBabyProvider = Provider<Baby?>((ref) {
  final babies = ref.watch(babiesStreamProvider).value ?? const [];
  return babies.isEmpty ? null : babies.first;
});

/// Feeding repository scoped to the current uid + current baby. Null when
/// signed out or no baby exists yet, so UI can guard cleanly.
final feedingRepositoryProvider = Provider<FeedingRepository?>((ref) {
  final user = ref.watch(authStateProvider).value;
  final baby = ref.watch(currentBabyProvider);
  if (user == null || baby == null) return null;
  return FeedingRepository(ref.watch(firestoreProvider), user.uid, baby.id);
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
  return DiaperRepository(ref.watch(firestoreProvider), user.uid, baby.id);
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
