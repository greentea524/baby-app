import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/pumping_event.dart';
import '../../data/repositories/repository_providers.dart';
import '../home/home_prefs.dart';
import 'amount_suggestions.dart';

/// One-tap amounts for the bottle form (#31).
///
/// Both streams are already live while the sheet is open — the home screen's
/// activity list and today's summary watch them, and the sheet opens over
/// home — so the suggestions cost no additional Firestore reads.
///
/// The pump half is gated on the caregiver having pumping switched on. A
/// household that hid the pumping action has said pumping is not part of
/// their day, and should not be offered chips flavoured by it.
final bottleAmountSuggestionsProvider = Provider<List<AmountSuggestion>>((ref) {
  final feeds = ref.watch(recentFeedingsProvider).value ?? const [];
  final pumps = ref.watch(showPumpingActionProvider)
      ? ref.watch(recentPumpingProvider).value ?? const <PumpingEvent>[]
      : const <PumpingEvent>[];
  return suggestedAmounts(feeds: feeds, pumps: pumps);
});
