class TriviaDataException implements Exception {
  const TriviaDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TriviaQuestion {
  const TriviaQuestion({
    required this.category,
    required this.difficulty,
    required this.type,
    required this.prompt,
    required this.correctAnswer,
    required this.incorrectAnswer,
    required this.encodedPrompt,
  });

  final String category;
  final String difficulty;
  final String type;
  final String prompt;
  final String correctAnswer;
  final String incorrectAnswer;
  final String encodedPrompt;

  bool isCorrect(String selection) => selection == correctAnswer;

  static TriviaQuestion fromApiJson(Map<String, dynamic> json) {
    String decodeRequired(String field) {
      final value = json[field];
      if (value is! String || value.isEmpty) {
        throw TriviaDataException('Question field "$field" is missing.');
      }
      try {
        final decoded = Uri.decodeComponent(value);
        if (decoded.trim().isEmpty) {
          throw TriviaDataException('Question field "$field" is empty.');
        }
        return decoded;
      } on ArgumentError {
        throw TriviaDataException('Question field "$field" has bad encoding.');
      }
    }

    final rawPrompt = json['question'];
    if (rawPrompt is! String || rawPrompt.isEmpty) {
      throw const TriviaDataException('Question text is missing.');
    }

    final incorrect = json['incorrect_answers'];
    if (incorrect is! List ||
        incorrect.length != 1 ||
        incorrect.first is! String) {
      throw const TriviaDataException(
        'A boolean question must have exactly one incorrect answer.',
      );
    }

    final category = decodeRequired('category');
    final difficulty = decodeRequired('difficulty');
    final type = decodeRequired('type');
    final prompt = decodeRequired('question');
    final correct = decodeRequired('correct_answer');
    late String incorrectValue;
    try {
      incorrectValue = Uri.decodeComponent(incorrect.first as String);
    } on ArgumentError {
      throw const TriviaDataException(
        'Question field "incorrect_answers" has bad encoding.',
      );
    }

    if (category != 'Science & Nature' ||
        difficulty != 'medium' ||
        type != 'boolean') {
      throw const TriviaDataException(
        'Question metadata does not match Class B.',
      );
    }
    if ({correct, incorrectValue}.length != 2 ||
        !{correct, incorrectValue}.containsAll(const {'True', 'False'})) {
      throw const TriviaDataException(
        'Question answers must be exactly True and False.',
      );
    }

    return TriviaQuestion(
      category: category,
      difficulty: difficulty,
      type: type,
      prompt: prompt,
      correctAnswer: correct,
      incorrectAnswer: incorrectValue,
      encodedPrompt: rawPrompt,
    );
  }
}
