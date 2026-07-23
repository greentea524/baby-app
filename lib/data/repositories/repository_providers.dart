import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../models/baby.dart';
import 'babies_repository.dart';

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
