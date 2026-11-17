class OperationIdentity {
  const OperationIdentity({required this.uid, required this.roundId});

  final String uid;
  final String roundId;

  bool isCurrent({
    required String? currentUid,
    required String currentRoundId,
  }) {
    return currentUid == uid && currentRoundId == roundId;
  }
}
