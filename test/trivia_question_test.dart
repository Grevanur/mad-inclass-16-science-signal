import 'package:flutter_test/flutter_test.dart';
import 'package:inclass_16/models/trivia_question.dart';

void main() {
  Map<String, dynamic> validQuestion({
    String question = 'The%20Earth%20orbits%20the%20Sun.',
    String correct = 'True',
    List<String> incorrect = const ['False'],
  }) {
    return {
      'category': 'Science%20%26%20Nature',
      'type': 'boolean',
      'difficulty': 'medium',
      'question': question,
      'correct_answer': correct,
      'incorrect_answers': incorrect,
    };
  }

  test('decodes the URL-3986 question and preserves the encoded evidence', () {
    final question = TriviaQuestion.fromApiJson(validQuestion());

    expect(question.prompt, 'The Earth orbits the Sun.');
    expect(question.category, 'Science & Nature');
    expect(question.encodedPrompt, 'The%20Earth%20orbits%20the%20Sun.');
    expect(question.isCorrect('True'), isTrue);
  });

  test('rejects malformed percent encoding', () {
    expect(
      () => TriviaQuestion.fromApiJson(validQuestion(question: 'Bad%ZZdata')),
      throwsA(isA<TriviaDataException>()),
    );
  });

  test('rejects invalid boolean answer values', () {
    expect(
      () => TriviaQuestion.fromApiJson(
        validQuestion(correct: 'Yes', incorrect: const ['No']),
      ),
      throwsA(isA<TriviaDataException>()),
    );
  });

  test('rejects anything other than one incorrect answer', () {
    expect(
      () => TriviaQuestion.fromApiJson(
        validQuestion(incorrect: const ['False', 'Maybe']),
      ),
      throwsA(isA<TriviaDataException>()),
    );
  });
}
