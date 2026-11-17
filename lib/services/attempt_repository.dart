import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

enum VerificationFault {
  none,
  permissionDeniedOnce,
  unavailable,
  resourceExhausted,
  acknowledgementTimeout,
}

enum CommitDisposition { created, reused }

class AttemptRecord {
  const AttemptRecord({
    required this.roundId,
    required this.correctCount,
    required this.submittedAt,
    required this.disposition,
  });

  final String roundId;
  final int correctCount;
  final Timestamp submittedAt;
  final CommitDisposition disposition;
}

class AttemptCollision implements Exception {
  const AttemptCollision(this.roundId);
  final String roundId;
}

class SaveUnknownException implements Exception {
  const SaveUnknownException(this.roundId);
  final String roundId;
}

class VerificationUnavailableException implements Exception {
  const VerificationUnavailableException(this.code, this.roundId);
  final String code;
  final String roundId;
}

class AttemptRepository {
  AttemptRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const schemaVersion = 1;
  static const variant = 'B';
  static const categoryId = 17;
  static const questionCount = 5;
  static const operationTimeout = Duration(seconds: 10);

  final FirebaseFirestore _firestore;
  bool _permissionFaultConsumed = false;

  static Map<String, dynamic> fixedPayloadForTest(int correctCount) {
    if (correctCount < 0 || correctCount > 5) {
      throw RangeError.range(correctCount, 0, 5, 'correctCount');
    }
    return {
      'schemaVersion': schemaVersion,
      'variant': variant,
      'categoryId': categoryId,
      'questionCount': questionCount,
      'correctCount': correctCount,
    };
  }

  DocumentReference<Map<String, dynamic>> reference(
    String uid,
    String roundId,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('attempts')
        .doc(roundId);
  }

  String newRoundId(String uid) =>
      _firestore.collection('users').doc(uid).collection('attempts').doc().id;

  Map<String, dynamic> fixedPayload(int correctCount) {
    return fixedPayloadForTest(correctCount);
  }

  Future<AttemptRecord> commitAndVerify({
    required String uid,
    required String roundId,
    required int correctCount,
    VerificationFault fault = VerificationFault.none,
  }) async {
    final ref = reference(uid, roundId);
    final payload = fixedPayload(correctCount);

    final transaction = _firestore.runTransaction<CommitDisposition>((
      tx,
    ) async {
      final current = await tx.get(ref);
      if (!current.exists) {
        tx.set(ref, {...payload, 'submittedAt': FieldValue.serverTimestamp()});
        return CommitDisposition.created;
      }
      final data = current.data();
      if (data == null || !_matchesFixedFields(data, payload)) {
        throw AttemptCollision(roundId);
      }
      return CommitDisposition.reused;
    });

    try {
      final disposition = fault == VerificationFault.acknowledgementTimeout
          ? await transaction
                .then((value) async {
                  await Future<void>.delayed(const Duration(seconds: 12));
                  return value;
                })
                .timeout(operationTimeout)
          : await transaction.timeout(operationTimeout);
      return await verifyExisting(
        uid: uid,
        roundId: roundId,
        expectedCorrectCount: correctCount,
        disposition: disposition,
        fault: fault,
      );
    } on TimeoutException {
      throw SaveUnknownException(roundId);
    }
  }

  Future<AttemptRecord> verifyExisting({
    required String uid,
    required String roundId,
    int? expectedCorrectCount,
    CommitDisposition disposition = CommitDisposition.reused,
    VerificationFault fault = VerificationFault.none,
  }) async {
    _injectVerificationFault(fault, roundId);

    late DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await reference(
        uid,
        roundId,
      ).get(const GetOptions(source: Source.server)).timeout(operationTimeout);
    } on TimeoutException {
      throw VerificationUnavailableException('deadline-exceeded', roundId);
    } on FirebaseException catch (error) {
      throw VerificationUnavailableException(error.code, roundId);
    }

    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw VerificationUnavailableException('not-found', roundId);
    }
    if (snapshot.metadata.hasPendingWrites) {
      throw VerificationUnavailableException('pending-writes', roundId);
    }
    final fixed = fixedPayload(
      expectedCorrectCount ?? _readCorrectCount(data, roundId),
    );
    if (!_matchesExactSchema(data, fixed) ||
        data['submittedAt'] is! Timestamp) {
      throw VerificationUnavailableException('schema-mismatch', roundId);
    }

    return AttemptRecord(
      roundId: roundId,
      correctCount: data['correctCount'] as int,
      submittedAt: data['submittedAt'] as Timestamp,
      disposition: disposition,
    );
  }

  int _readCorrectCount(Map<String, dynamic> data, String roundId) {
    final score = data['correctCount'];
    if (score is! int || score < 0 || score > 5) {
      throw VerificationUnavailableException('schema-mismatch', roundId);
    }
    return score;
  }

  void _injectVerificationFault(VerificationFault fault, String roundId) {
    switch (fault) {
      case VerificationFault.none:
      case VerificationFault.acknowledgementTimeout:
        return;
      case VerificationFault.permissionDeniedOnce:
        if (_permissionFaultConsumed) return;
        _permissionFaultConsumed = true;
        throw VerificationUnavailableException('permission-denied', roundId);
      case VerificationFault.unavailable:
        throw VerificationUnavailableException('unavailable', roundId);
      case VerificationFault.resourceExhausted:
        throw VerificationUnavailableException('resource-exhausted', roundId);
    }
  }

  bool _matchesFixedFields(
    Map<String, dynamic> actual,
    Map<String, dynamic> expected,
  ) {
    return expected.entries.every((entry) => actual[entry.key] == entry.value);
  }

  bool _matchesExactSchema(
    Map<String, dynamic> actual,
    Map<String, dynamic> expected,
  ) {
    const requiredKeys = {
      'schemaVersion',
      'variant',
      'categoryId',
      'questionCount',
      'correctCount',
      'submittedAt',
    };
    return actual.keys.toSet().difference(requiredKeys).isEmpty &&
        requiredKeys.difference(actual.keys.toSet()).isEmpty &&
        _matchesFixedFields(actual, expected);
  }
}
