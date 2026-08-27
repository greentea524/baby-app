import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/data/models/baby.dart';
import 'package:baby_app/data/repositories/account_data.dart';

/// What deleting an account is allowed to reach (#28, scope B).
void main() {
  Baby baby(String id, String owner, {List<String> others = const []}) => Baby(
    id: id,
    name: id,
    birthDate: DateTime(2026, 2, 1),
    ownerUid: owner,
    members: {
      owner: CaregiverRole.owner,
      for (final uid in others) uid: CaregiverRole.editor,
    },
  );

  test('deletes what you own', () {
    final split = AccountData.split([baby('ada', 'me')], 'me');
    expect(split.owned.map((b) => b.id), ['ada']);
    expect(split.shared, isEmpty);
  });

  test("and only leaves what you don't", () {
    // A caregiver invited to someone else's baby has no business destroying
    // it on the way out — and the rules would refuse: a member may remove
    // exactly themselves.
    final split = AccountData.split(
      [baby('theirs', 'someone', others: ['me'])],
      'me',
    );
    expect(split.owned, isEmpty);
    expect(split.shared.map((b) => b.id), ['theirs']);
  });

  test('sorts a household that has both', () {
    final split = AccountData.split([
      baby('mine', 'me', others: ['partner']),
      baby('theirs', 'partner', others: ['me']),
      baby('also-mine', 'me'),
    ], 'me');

    expect(split.owned.map((b) => b.id), ['mine', 'also-mine']);
    expect(split.shared.map((b) => b.id), ['theirs']);
  });

  test('owning it is about ownership, not membership', () {
    // Being on the roster of your own baby must not put it in both lists.
    final split = AccountData.split([baby('ada', 'me', others: ['x'])], 'me');
    expect(split.owned.length, 1);
    expect(split.shared, isEmpty);
  });

  test('an account with nothing on it still splits cleanly', () {
    final split = AccountData.split(const [], 'me');
    expect(split.owned, isEmpty);
    expect(split.shared, isEmpty);
  });
}
