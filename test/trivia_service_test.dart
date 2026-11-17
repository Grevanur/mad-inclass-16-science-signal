import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inclass_16/models/trivia_question.dart';
import 'package:inclass_16/services/trivia_service.dart';

void main() {
  Map<String, dynamic> item(int index) => {
    'category': 'Science%20%26%20Nature',
    'type': 'boolean',
    'difficulty': 'medium',
    'question': 'Encoded%20question%20$index%3F',
    'correct_answer': index.isEven ? 'True' : 'False',
    'incorrect_answers': [index.isEven ? 'False' : 'True'],
  };

  OpenTriviaService serviceFor(Map<String, dynamic> body, {int status = 200}) {
    return OpenTriviaService(
      client: MockClient((_) async => http.Response(jsonEncode(body), status)),
    );
  }

  test('accepts exactly five valid Class B results', () async {
    final service = serviceFor({
      'response_code': 0,
      'results': List.generate(5, item),
    });

    final questions = await service.fetchQuestions();

    expect(questions, hasLength(5));
    expect(questions.first.prompt, 'Encoded question 0?');
  });

  test('rejects a nonzero API response code', () {
    final service = serviceFor({'response_code': 1, 'results': []});

    expect(service.fetchQuestions(), throwsA(isA<TriviaDataException>()));
  });

  test('rejects a four-result response', () {
    final service = serviceFor({
      'response_code': 0,
      'results': List.generate(4, item),
    });

    expect(service.fetchQuestions(), throwsA(isA<TriviaDataException>()));
  });

  test('rejects a successful HTTP response with invalid answers', () {
    final results = List.generate(5, item);
    results[2] = {...results[2], 'correct_answer': 'Maybe'};
    final service = serviceFor({'response_code': 0, 'results': results});

    expect(service.fetchQuestions(), throwsA(isA<TriviaDataException>()));
  });

  test('rejects a non-200 HTTP response', () {
    final service = serviceFor({}, status: 503);

    expect(service.fetchQuestions(), throwsA(isA<TriviaDataException>()));
  });

  test('rate-limits a second request from the same service', () async {
    final service = serviceFor({
      'response_code': 0,
      'results': List.generate(5, item),
    });
    await service.fetchQuestions();

    expect(service.fetchQuestions(), throwsA(isA<TriviaDataException>()));
  });
}
