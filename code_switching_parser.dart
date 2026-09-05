/// معالجة وتنسيق النصوص التي تمزج بين العربية والفرنسية والدارجة الجزائرية
/// (Code-Switching) — يعمل على مستوى التنسيق البصري وعلامات الترقيم فقط،
/// وليس ترجمة أو تصحيحاً نحوياً حقيقياً.
class CodeSwitchingParser {
  static String formatMixedLanguageText(String rawText) {
    if (rawText.isEmpty) return '';

    String cleanedText = rawText;

    // 1. تصحيح اتجاهات النصوص المزدوجة (RTL/LTR) لضمان عرض سليم
    //    للكلمات الفرنسية/اللاتينية داخل جملة عربية
    cleanedText = _fixBiDiDirection(cleanedText);

    // 2. تنقيح علامات الترقيم في الجمل المختلطة
    cleanedText = cleanedText
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\s+,'), '،')
        .replaceAll(RegExp(r'\s+\?'), '؟');

    return cleanedText.trim();
  }

  /// إضافة علامة Right-to-Left Mark في بداية كل سطر لتفادي التباس اتجاه
  /// العرض عندما يبدأ السطر أو ينتهي بكلمة لاتينية (فرنسية/إنجليزية)
  static String _fixBiDiDirection(String text) {
    const String rlm = '\u200F';
    return text.split('\n').map((line) {
      if (line.trim().isEmpty) return line;
      return '$rlm$line';
    }).join('\n');
  }
}
