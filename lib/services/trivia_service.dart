import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/trivia_question.dart';

abstract interface class TriviaSource {
  Duration get retryDelayRemaining;
  Future<List<TriviaQuestion>> fetchQuestions();
}

class OpenTriviaService implements TriviaSource {
  OpenTriviaService({http.Client? client}) : _client = client ?? http.Client();

  static final Uri endpoint = Uri.parse(
    'https://opentdb.com/api.php?amount=5&category=17&difficulty=medium'
    '&type=boolean&encode=url3986',
  );
  static const _minimumRequestGap = Duration(seconds: 5);
  DateTime? _lastRequestAt;

  final http.Client _client;

  @override
  Duration get retryDelayRemaining {
    final last = _lastRequestAt;
    if (last == null) return Duration.zero;
    final remaining = _minimumRequestGap - DateTime.now().difference(last);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  Future<List<TriviaQuestion>> fetchQuestions() async {
    final remaining = retryDelayRemaining;
    if (remaining > Duration.zero) {
      throw TriviaDataException(
        'Please wait ${remaining.inSeconds + 1} seconds before retrying.',
      );
    }
    _lastRequestAt = DateTime.now();

    late http.Response response;
    try {
      response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const TriviaDataException(
        'Question request timed out after 10 seconds.',
      );
    } on Exception {
      throw const TriviaDataException(
        'Question service is currently unavailable.',
      );
    }

    if (response.statusCode != 200) {
      throw TriviaDataException(
        'Question service returned HTTP ${response.statusCode}.',
      );
    }

    late Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      body = decoded;
    } on FormatException {
      throw const TriviaDataException('Question response is not valid JSON.');
    }

    if (body['response_code'] != 0) {
      throw TriviaDataException(
        'Question API rejected the request (code ${body['response_code']}).',
      );
    }
    final results = body['results'];
    if (results is! List || results.length != 5) {
      throw const TriviaDataException(
        'Question response must contain exactly five results.',
      );
    }

    try {
      return results
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const TriviaDataException('A question result is invalid.');
            }
            return TriviaQuestion.fromApiJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const TriviaDataException(
        'Question response has malformed encoding.',
      );
    }
  }
}
