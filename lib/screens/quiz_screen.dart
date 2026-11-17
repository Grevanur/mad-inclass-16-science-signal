import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/result_binding.dart';
import '../models/trivia_question.dart';
import '../services/attempt_repository.dart';
import '../services/trivia_service.dart';

enum RoundPhase {
  loading,
  requestError,
  playing,
  readyToSubmit,
  submitting,
  verifying,
  saveUnknown,
  verificationUnavailable,
  permissionDenied,
  cloudVerified,
  collision,
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.user});

  final User user;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final TriviaSource _trivia = OpenTriviaService();
  final AttemptRepository _attempts = AttemptRepository();
  final _retrieveController = TextEditingController();

  List<TriviaQuestion> _questions = const [];
  final List<String?> _selections = List<String?>.filled(5, null);
  int _index = 0;
  late String _roundId;
  RoundPhase _phase = RoundPhase.loading;
  String _message = 'Requesting five validated science questions…';
  AttemptRecord? _verified;
  VerificationFault _fault = VerificationFault.none;

  bool get _unresolved => {
    RoundPhase.submitting,
    RoundPhase.verifying,
    RoundPhase.saveUnknown,
    RoundPhase.verificationUnavailable,
    RoundPhase.permissionDenied,
  }.contains(_phase);

  int get _score {
    var total = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_selections[i] == _questions[i].correctAnswer) total++;
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    _roundId = _attempts.newRoundId(widget.user.uid);
    _loadQuestions();
  }

  @override
  void dispose() {
    _retrieveController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _phase = RoundPhase.loading;
      _message = 'Requesting five validated science questions…';
    });
    try {
      final questions = await _trivia.fetchQuestions();
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _phase = RoundPhase.playing;
        _message = 'Question 1 of 5';
      });
    } on TriviaDataException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = RoundPhase.requestError;
        _message = error.message;
      });
    }
  }

  void _select(String value) {
    if (_phase != RoundPhase.playing || _selections[_index] != null) return;
    setState(() {
      _selections[_index] = value;
      _message = _questions[_index].isCorrect(value)
          ? 'Correct — evidence matches.'
          : 'Not quite — review the verified answer below.';
    });
  }

  void _continue() {
    if (_selections[_index] == null) return;
    if (_index == 4) {
      setState(() {
        _phase = RoundPhase.readyToSubmit;
        _message = 'Round complete. Review all five answers before saving.';
      });
      return;
    }
    setState(() {
      _index++;
      _message = 'Question ${_index + 1} of 5';
    });
  }

  Future<void> _submit() async {
    if (_phase != RoundPhase.readyToSubmit && _phase != RoundPhase.collision) {
      return;
    }
    final identity = OperationIdentity(uid: widget.user.uid, roundId: _roundId);
    final capturedScore = _score;
    setState(() {
      _phase = RoundPhase.submitting;
      _message = 'Creating or reconciling the immutable cloud attempt…';
    });
    try {
      setState(() {
        _phase = RoundPhase.verifying;
        _message = 'Write acknowledged. Verifying the exact server document…';
      });
      final record = await _attempts.commitAndVerify(
        uid: identity.uid,
        roundId: identity.roundId,
        correctCount: capturedScore,
        fault: kDebugMode ? _fault : VerificationFault.none,
      );
      if (!_mayApply(identity)) return;
      setState(() {
        _verified = record;
        _phase = RoundPhase.cloudVerified;
        _message = 'Cloud verified — server record matches this round.';
      });
    } on AttemptCollision {
      if (!_mayApply(identity)) return;
      setState(() {
        _phase = RoundPhase.collision;
        _message = 'Collision: this round ID already has a different payload.';
      });
    } on SaveUnknownException {
      if (!_mayApply(identity)) return;
      setState(() {
        _phase = RoundPhase.saveUnknown;
        _message =
            'Save outcome unknown. Reconcile this original ID before retrying.';
      });
    } on VerificationUnavailableException catch (error) {
      if (!_mayApply(identity)) return;
      setState(() {
        _phase = error.code == 'permission-denied'
            ? RoundPhase.permissionDenied
            : RoundPhase.verificationUnavailable;
        _message =
            'Write acknowledged; verification unavailable (${error.code}).';
      });
    }
  }

  Future<void> _reconcile() async {
    if (!_unresolved) return;
    final identity = OperationIdentity(uid: widget.user.uid, roundId: _roundId);
    setState(() {
      _phase = RoundPhase.verifying;
      _message = 'Reading the original ID from the server…';
    });
    try {
      final record = await _attempts.verifyExisting(
        uid: identity.uid,
        roundId: identity.roundId,
        expectedCorrectCount: _score,
      );
      if (!_mayApply(identity)) return;
      setState(() {
        _verified = record;
        _phase = RoundPhase.cloudVerified;
        _message =
            'Cloud verified — original ID confirmed without a second write.';
      });
    } on VerificationUnavailableException catch (error) {
      if (!_mayApply(identity)) return;
      setState(() {
        _phase = error.code == 'permission-denied'
            ? RoundPhase.permissionDenied
            : RoundPhase.verificationUnavailable;
        _message = 'Verification still unavailable (${error.code}).';
      });
    }
  }

  Future<void> _retrievePrior() async {
    final id = _retrieveController.text.trim();
    if (id.isEmpty || _unresolved) return;
    final identity = OperationIdentity(uid: widget.user.uid, roundId: id);
    setState(() => _message = 'Retrieving $id from the server…');
    try {
      final record = await _attempts.verifyExisting(
        uid: identity.uid,
        roundId: identity.roundId,
      );
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != identity.uid) {
        return;
      }
      setState(() {
        _verified = record;
        _message =
            'Server record retrieved: ${record.correctCount}/5, ID …${_suffix(id)}.';
      });
    } on VerificationUnavailableException catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Retrieval failed (${error.code}).');
    }
  }

  bool _mayApply(OperationIdentity identity) {
    if (!mounted) return false;
    return identity.isCurrent(
      currentUid: FirebaseAuth.instance.currentUser?.uid,
      currentRoundId: _roundId,
    );
  }

  void _replay() {
    if (_unresolved) return;
    setState(() {
      _roundId = _attempts.newRoundId(widget.user.uid);
      _questions = const [];
      _selections.fillRange(0, _selections.length, null);
      _index = 0;
      _verified = null;
      _fault = VerificationFault.none;
    });
    _loadQuestions();
  }

  String _suffix(String value) =>
      value.length <= 6 ? value : value.substring(value.length - 6);

  Color _statusColor(BuildContext context) {
    return switch (_phase) {
      RoundPhase.cloudVerified => const Color(0xFF39D98A),
      RoundPhase.requestError ||
      RoundPhase.collision ||
      RoundPhase.permissionDenied => Theme.of(context).colorScheme.error,
      RoundPhase.saveUnknown ||
      RoundPhase.verificationUnavailable => const Color(0xFFFFC857),
      _ => const Color(0xFF72C7FF),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Science Signal'),
        actions: [
          IconButton(
            tooltip: _unresolved
                ? 'Resolve the cloud attempt before signing out'
                : 'Sign out',
            onPressed: _unresolved ? null : FirebaseAuth.instance.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _identityCard(context),
            const SizedBox(height: 14),
            _statusCard(context),
            const SizedBox(height: 14),
            if (_phase == RoundPhase.loading) _loadingCard(),
            if (_phase == RoundPhase.requestError) _requestErrorCard(),
            if (_phase == RoundPhase.playing) _questionCard(context),
            if ({
              RoundPhase.readyToSubmit,
              RoundPhase.submitting,
              RoundPhase.verifying,
              RoundPhase.saveUnknown,
              RoundPhase.verificationUnavailable,
              RoundPhase.permissionDenied,
              RoundPhase.cloudVerified,
              RoundPhase.collision,
            }.contains(_phase))
              _reviewCard(context),
            const SizedBox(height: 14),
            _retrievalCard(),
            if (kDebugMode) ...[const SizedBox(height: 14), _evidenceLab()],
          ],
        ),
      ),
    );
  }

  Widget _identityCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AUTHENTICATED OWNER',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 3),
                  Text('UID …${_suffix(widget.user.uid)}'),
                ],
              ),
            ),
            Text(
              'ID …${_suffix(_roundId)}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final color = _statusColor(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('statusCard'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.75)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _phase == RoundPhase.cloudVerified
                  ? Icons.cloud_done_outlined
                  : _unresolved
                  ? Icons.cloud_sync_outlined
                  : Icons.info_outline,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(_message, key: const Key('statusMessage'))),
          ],
        ),
      ),
    );
  }

  Widget _loadingCard() => const Card(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text(
            'Validating HTTP status, response code, metadata, and answer set.',
          ),
        ],
      ),
    ),
  );

  Widget _requestErrorCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Questions were not accepted.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'No playable state was created from the invalid response.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _trivia.retryDelayRemaining > Duration.zero
                ? null
                : _loadQuestions,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry request'),
          ),
        ],
      ),
    ),
  );

  Widget _questionCard(BuildContext context) {
    final question = _questions[_index];
    final selected = _selections[_index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'QUESTION ${_index + 1} / 5',
                  style: const TextStyle(letterSpacing: 1.4),
                ),
                const Spacer(),
                Text(
                  'Score $_score',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: (_index + 1) / 5),
            const SizedBox(height: 22),
            Text(
              question.prompt,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            for (final value in const ['True', 'False']) ...[
              OutlinedButton.icon(
                key: Key('answer$value'),
                onPressed: selected == null ? () => _select(value) : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(
                    color: selected == value
                        ? (question.isCorrect(value)
                              ? const Color(0xFF39D98A)
                              : Theme.of(context).colorScheme.error)
                        : const Color(0xFF39515C),
                    width: selected == value ? 2 : 1,
                  ),
                ),
                icon: Icon(
                  selected == value
                      ? (question.isCorrect(value)
                            ? Icons.check_circle
                            : Icons.cancel)
                      : Icons.circle_outlined,
                ),
                label: Text(value),
              ),
              const SizedBox(height: 10),
            ],
            if (selected != null) ...[
              Text(
                question.isCorrect(selected)
                    ? '✓ Correct answer: ${question.correctAnswer}'
                    : '✕ Your answer: $selected · Correct: ${question.correctAnswer}',
                key: const Key('answerFeedback'),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              key: const Key('continueButton'),
              onPressed: selected == null ? null : _continue,
              child: Text(_index == 4 ? 'Review round' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review · $_score / 5',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _questions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _selections[i] == _questions[i].correctAnswer
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: _selections[i] == _questions[i].correctAnswer
                          ? const Color(0xFF39D98A)
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${i + 1}. ${_questions[i].prompt}\n'
                        'Your answer: ${_selections[i]} · '
                        'Correct: ${_questions[i].correctAnswer}',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            if (_phase == RoundPhase.readyToSubmit ||
                _phase == RoundPhase.collision)
              FilledButton.icon(
                key: const Key('submitButton'),
                onPressed: _submit,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Submit immutable attempt'),
              ),
            if (_unresolved)
              FilledButton.icon(
                key: const Key('reconcileButton'),
                onPressed: _phase == RoundPhase.verifying ? null : _reconcile,
                icon: const Icon(Icons.manage_search),
                label: const Text('Reconcile original ID'),
              ),
            if (_phase == RoundPhase.cloudVerified) ...[
              SelectableText(
                'Verified ID: $_roundId\n'
                'Server timestamp: '
                '${_verified?.submittedAt.toDate().toUtc().toIso8601String()}',
                key: const Key('verifiedRecord'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                key: const Key('replayButton'),
                onPressed: _replay,
                icon: const Icon(Icons.replay),
                label: const Text('Start a new round'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _retrievalCard() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.cloud_download_outlined),
        title: const Text('Retrieve an existing round'),
        subtitle: const Text('Server-only restart verification'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            key: const Key('retrieveRoundField'),
            controller: _retrieveController,
            enabled: !_unresolved,
            decoration: const InputDecoration(labelText: 'Full round ID'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('retrieveButton'),
              onPressed: _unresolved ? null : _retrievePrior,
              child: const Text('Read from server'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _evidenceLab() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: const Text('Development evidence lab'),
        subtitle: const Text('Labeled fault injection · rules stay deployed'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          DropdownButtonFormField<VerificationFault>(
            initialValue: _fault,
            decoration: const InputDecoration(
              labelText: 'Next submission fault',
            ),
            items: VerificationFault.values
                .map(
                  (fault) =>
                      DropdownMenuItem(value: fault, child: Text(fault.name)),
                )
                .toList(),
            onChanged: _unresolved
                ? null
                : (value) =>
                      setState(() => _fault = value ?? VerificationFault.none),
          ),
          const SizedBox(height: 10),
          const Text(
            'Faults affect only the development repository response. '
            'The transaction and final reconciliation use the deployed cloud project.',
            style: TextStyle(fontSize: 12, color: Color(0xFF9DB0BA)),
          ),
        ],
      ),
    );
  }
}
