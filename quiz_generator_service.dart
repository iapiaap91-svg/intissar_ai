import 'dart:math';

class QuizQuestion {
  final String id;
  final String questionText;
  final List<String> options;
  final int correctOptionIndex;
  final String explanation;

  QuizQuestion({
    required this.id,
    required this.questionText,
    required this.options,
    required this.correctOptionIndex,
    required this.explanation,
  });
}

/// مولّد اختبارات محلي حقيقي يعمل فعلياً على محتوى المحاضرة المُمرَّر إليه.
///
/// الأسلوب: استخراجي بالكامل (extractive) — يختار جملاً غنية بالمعلومات من
/// النص نفسه، يحذف منها كلمة مفتاحية مهمة (اسماً أو مصطلحاً)، ويطلب من
/// المستخدم اختيار الكلمة الصحيحة من بين مموِّهات (distractors) مأخوذة من
/// كلمات أخرى وردت في نفس النص.
///
/// صراحة تقنية: هذا **ليس** توليداً ذكياً لأسئلة فهم أو استنتاج — الأسئلة
/// كلها من نمط "أكمل الفراغ" المبني مباشرة على جمل موجودة حرفياً في النص.
/// جودة الأسئلة تعتمد كلياً على جودة وطول النص المُدخل: نص قصير أو ضعيف
/// التنظيم ينتج أسئلة ضعيفة.
class QuizGeneratorService {
  final Random _random = Random();

  Future<List<QuizQuestion>> generateQuizFromContent(
    String content, {
    int maxQuestions = 5,
  }) async {
    final sentences = _extractCandidateSentences(content);
    if (sentences.isEmpty) return [];

    final allKeywords = _extractAllKeywords(content);
    if (allKeywords.length < 4) {
      // لا توجد كلمات كافية لبناء مموِّهات ذات معنى
      return [];
    }

    final questions = <QuizQuestion>[];
    var qIndex = 0;

    for (final sentence in sentences) {
      if (questions.length >= maxQuestions) break;

      final keywordInSentence = _pickKeywordFromSentence(sentence, allKeywords);
      if (keywordInSentence == null) continue;

      final blankedSentence = sentence.replaceFirst(
        RegExp('\\b${RegExp.escape(keywordInSentence)}\\b'),
        '______',
      );
      if (blankedSentence == sentence) continue; // لم يتم استبدال شيء فعلياً

      final distractors = _pickDistractors(keywordInSentence, allKeywords, count: 3);
      if (distractors.length < 3) continue;

      final options = [keywordInSentence, ...distractors]..shuffle(_random);
      final correctIndex = options.indexOf(keywordInSentence);

      qIndex++;
      questions.add(QuizQuestion(
        id: 'q$qIndex',
        questionText: 'أكمل الفراغ: $blankedSentence',
        options: options,
        correctOptionIndex: correctIndex,
        explanation: 'الجملة كاملة كما وردت في المحتوى: "$sentence"',
      ));
    }

    return questions;
  }

  bool evaluateAnswer(QuizQuestion question, int selectedIndex) {
    return question.correctOptionIndex == selectedIndex;
  }

  List<String> _extractCandidateSentences(String content) {
    return content
        .split(RegExp(r'(?<=[.!؟?\n])'))
        .map((s) => s.trim())
        .where((s) => s.split(RegExp(r'\s+')).length >= 5 && s.length < 200)
        .toList();
  }

  List<String> _extractAllKeywords(String content) {
    final tokens = content
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3)
        .toList();

    // تفضيل الكلمات الأطول والأقل تكراراً كمرشحين لمصطلحات ذات معنى
    final frequency = <String, int>{};
    for (final t in tokens) {
      frequency[t] = (frequency[t] ?? 0) + 1;
    }
    final unique = frequency.keys.where((k) => frequency[k]! <= 3).toList();
    unique.sort((a, b) => b.length.compareTo(a.length));
    return unique;
  }

  String? _pickKeywordFromSentence(String sentence, List<String> allKeywords) {
    final words = sentence.split(RegExp(r'\s+'));
    final candidates = words.where((w) => allKeywords.contains(w)).toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }

  List<String> _pickDistractors(String correct, List<String> pool, {required int count}) {
    final candidates = pool.where((k) => k != correct).toList()..shuffle(_random);
    return candidates.take(count).toList();
  }
}
