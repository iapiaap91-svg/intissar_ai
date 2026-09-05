import 'dart:io';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

/// خدمة استخراج نص حقيقي من الصور (سبورة، ورقة امتحان، كتاب) عبر Tesseract
/// OCR — تعمل بالكامل على الجهاز دون إنترنت، وتدعم العربية والفرنسية معاً.
///
/// ملاحظات دقة صريحة:
/// - Tesseract مصمم للنص المطبوع (كتب، شرائح، مستندات ممسوحة بجودة جيدة).
/// - دقته على **الخط اليدوي** (كتابة الأستاذ على السبورة مثلاً) ضعيفة جداً؛
///   لا يوجد حالياً حل تعرّف بصري على الخط اليدوي العربي يعمل محلياً على
///   الجوال بدقة موثوقة — هذا قيد تقني حقيقي وليس نقص تنفيذ فقط.
/// - يتطلب وضع ملفات بيانات اللغة (ara.traineddata, fra.traineddata)
///   يدوياً في مجلد tessdata/ (راجع README).
class VisionOCRService {
  /// استخراج النص من صورة بلغة واحدة أو أكثر (مثال: 'ara+fra' لعربي+فرنسي مختلط)
  Future<String> extractTextFromImage(
    String imagePath, {
    String languages = 'ara+fra',
  }) async {
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw Exception('الصورة غير موجودة: $imagePath');
    }

    final String text = await FlutterTesseractOcr.extractText(
      imagePath,
      language: languages,
      args: {
        "psm": "3",
        "preserve_interword_spaces": "1",
      },
    );

    return text.trim();
  }
}
