import 'package:flutter_test/flutter_test.dart';
import 'package:inclass_16/core/result_binding.dart';
import 'package:inclass_16/services/attempt_repository.dart';

void main() {
  test('fixed payload contains the five immutable non-timestamp fields', () {
    final payload = AttemptRepository.fixedPayloadForTest(3);

    expect(payload, {
      'schemaVersion': 1,
      'variant': 'B',
      'categoryId': 17,
      'questionCount': 5,
      'correctCount': 3,
    });
  });

  test('score outside 0 through 5 is rejected', () {
    expect(() => AttemptRepository.fixedPayloadForTest(6), throwsRangeError);
  });

  test('stale UID response cannot update the current user', () {
    const operation = OperationIdentity(uid: 'user-a', roundId: 'round-1');

    expect(
      operation.isCurrent(currentUid: 'user-b', currentRoundId: 'round-1'),
      isFalse,
    );
  });

  test('cross-round response cannot update another round', () {
    const operation = OperationIdentity(uid: 'user-a', roundId: 'round-1');

    expect(
      operation.isCurrent(currentUid: 'user-a', currentRoundId: 'round-2'),
      isFalse,
    );
  });
}
