/// محرك إجابة محلي قائم على الاسترجاع الاستخراجي (Extractive Retrieval).
///
/// صراحة تقنية: هذا **ليس** نموذج لغوي توليدي (Generative LLM) — لا يوجد
/// "فهم" حقيقي للسؤال، بل تسجيل تشابه كلمات مفتاحية بين السؤال وجمل السياق،
/// ثم إرجاع أكثر الجمل صلة كإجابة "بأسلوب اقتباس". هذا يعمل بشكل معقول
/// للأسئلة المباشرة ("ماذا قال المحاضر عن X؟") لكنه لا يستنتج أو يلخّص
/// أو يربط بين فقرات متباعدة.
///
/// لبناء محرك توليدي حقيقي (يفهم السياق ويصوغ إجابة جديدة) يلزم دمج نموذج
/// لغوي مضغوط يعمل على الجهاز عبر مكتبات مثل llama.cpp أو MLC-LLM
/// (حزمة `fllama` في Flutter مثلاً) — وهذا يتطلب تحميل ملف نموذج بحجم
/// 1-4 جيجابايت تقريباً، وموازنة صريحة بين الدقة وسرعة الاستجابة على
/// جهاز محمول. هذه نقطة تستحق نقاشاً منفصلاً قبل التنفيذ.
class LocalRAGService {
  static const List<String> _arabicStopWords = [
    'من', 'في', 'على', 'إلى', 'عن', 'مع', 'هذا', 'هذه', 'ذلك', 'التي',
    'الذي', 'هو', 'هي', 'كان', 'كانت', 'ما', 'لا', 'أن', 'إن', 'كل',
    'بعد', 'قبل', 'كيف', 'ماذا', 'هل', 'و', 'ثم', 'أو', 'لم', 'لن',
  ];
  static const List<String> _frenchStopWords = [
    'le', 'la', 'les', 'de', 'des', 'du', 'un', 'une', 'et', 'est',
    'que', 'qui', 'dans', 'pour', 'sur', 'avec', 'ce', 'cette', 'comment',
  ];

  /// الإجابة عن سؤال بالبحث عن أكثر الجمل صلة في سياق الدرس/المستندات/الصورة
  Future<RAGAnswer> answerQuestion({
    required String question,
    required String lessonContext,
    String? imageOCRContext,
  }) async {
    final combinedContext = StringBuffer(lessonContext);
    if (imageOCRContext != null && imageOCRContext.trim().isNotEmpty) {
      combinedContext.writeln();
      combinedContext.write(imageOCRContext);
    }

    final sentences = _splitIntoSentences(combinedContext.toString());
    if (sentences.isEmpty) {
      return RAGAnswer(
        answerText: 'لا يوجد سياق كافٍ (نص محاضرة أو مستند) للإجابة على هذا السؤال.',
        matchedSentences: const [],
        confidence: 0,
      );
    }

    final questionKeywords = _extractKeywords(question);
    if (questionKeywords.isEmpty) {
      return RAGAnswer(
        answerText: 'لم أتمكن من تحديد كلمات مفتاحية واضحة في السؤال.',
        matchedSentences: const [],
        confidence: 0,
      );
    }

    final scored = <_ScoredSentence>[];
    for (final sentence in sentences) {
      final sentenceKeywords = _extractKeywords(sentence);
      final overlap = questionKeywords.intersection(sentenceKeywords).length;
      if (overlap > 0) {
        final score = overlap / questionKeywords.length;
        scored.add(_ScoredSentence(sentence, score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final topMatches = scored.take(3).toList();

    if (topMatches.isEmpty) {
      return RAGAnswer(
        answerText:
            'لم أجد في السياق المتوفر (التسجيل/المستند/الصورة) ما يتعلق مباشرة بهذا السؤال. '
            'حاول إعادة صياغة السؤال أو التأكد أن الدرس المرتبط تم تفريغه بالكامل.',
        matchedSentences: const [],
        confidence: 0,
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('📌 بناءً على السياق المتوفر، أقرب الفقرات صلة بسؤالك:');
    buffer.writeln();
    for (var i = 0; i < topMatches.length; i++) {
      buffer.writeln('${i + 1}. ${topMatches[i].sentence.trim()}');
    }

    return RAGAnswer(
      answerText: buffer.toString().trim(),
      matchedSentences: topMatches.map((m) => m.sentence).toList(),
      confidence: topMatches.first.score,
    );
  }

  List<String> _splitIntoSentences(String text) {
    return text
        .split(RegExp(r'(?<=[.!؟?\n])'))
        .map((s) => s.trim())
        .where((s) => s.length > 3)
        .toList();
  }

  Set<String> _extractKeywords(String text) {
    final tokens = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toSet();
    tokens.removeAll(_arabicStopWords);
    tokens.removeAll(_frenchStopWords);
    return tokens;
  }
}

class _ScoredSentence {
  final String sentence;
  final double score;
  _ScoredSentence(this.sentence, this.score);
}

class RAGAnswer {
  final String answerText;
  final List<String> matchedSentences;
  final double confidence; // 0.0 إلى 1.0 — نسبة تقاطع الكلمات المفتاحية فقط

  RAGAnswer({
    required this.answerText,
    required this.matchedSentences,
    required this.confidence,
  });
}
