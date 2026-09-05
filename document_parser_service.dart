import 'dart:io';
import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

/// خدمة استيراد وقراءة المستندات — تستخرج نصاً حقيقياً (وليس محاكاة) من
/// ملفات PDF وWord (.docx) وPowerPoint (.pptx) بالكامل محلياً دون إنترنت.
class DocumentParserService {
  /// استخراج النص الكامل من ملف PDF باستخدام Syncfusion PdfTextExtractor
  Future<String> extractTextFromPDF(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ملف PDF غير موجود: $filePath');
    }

    final bytes = await file.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);

    final buffer = StringBuffer();
    for (int i = 0; i < document.pages.count; i++) {
      final pageText = PdfTextExtractor(document).extractText(
        startPageIndex: i,
        endPageIndex: i,
      );
      buffer.writeln('--- الصفحة ${i + 1} ---');
      buffer.writeln(pageText.trim());
      buffer.writeln();
    }

    document.dispose();
    return buffer.toString().trim();
  }

  /// استخراج النص من ملف Word (.docx) عبر فك أرشيف ZIP وتحليل word/document.xml
  Future<String> extractTextFromDocx(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ملف Word غير موجود: $filePath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final documentEntry = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw Exception('الملف تالف أو ليس ملف .docx صالحاً'),
    );

    final xmlContent = String.fromCharCodes(documentEntry.content as List<int>);
    final document = XmlDocument.parse(xmlContent);

    // كل نص فعلي في Word موجود داخل عناصر <w:t>
    final textNodes = document.findAllElements('t', namespace: '*');
    final buffer = StringBuffer();
    for (final node in textNodes) {
      buffer.write(node.innerText);
      // فصل الفقرات تقريبياً عند نهاية كل عنصر نصي متبوع بعنصر فقرة جديدة
    }

    return _insertParagraphBreaks(document, buffer.toString());
  }

  /// استخراج النص من ملف PowerPoint (.pptx) عبر فك أرشيف ZIP وتحليل كل شرائح ppt/slides
  Future<String> extractTextFromPptx(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ملف PowerPoint غير موجود: $filePath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final slideFiles = archive.files
        .where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
        .toList()
      ..sort((a, b) {
        final numA = int.parse(RegExp(r'\d+').firstMatch(a.name)!.group(0)!);
        final numB = int.parse(RegExp(r'\d+').firstMatch(b.name)!.group(0)!);
        return numA.compareTo(numB);
      });

    if (slideFiles.isEmpty) {
      throw Exception('الملف تالف أو ليس ملف .pptx صالحاً');
    }

    final buffer = StringBuffer();
    for (var i = 0; i < slideFiles.length; i++) {
      final xmlContent = String.fromCharCodes(slideFiles[i].content as List<int>);
      final document = XmlDocument.parse(xmlContent);
      // كل نص فعلي في PowerPoint موجود داخل عناصر <a:t>
      final textNodes = document.findAllElements('t', namespace: '*');
      buffer.writeln('--- الشريحة ${i + 1} ---');
      for (final node in textNodes) {
        buffer.writeln(node.innerText);
      }
      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  /// نقطة دخول موحدة تختار طريقة الاستخراج المناسبة حسب امتداد الملف
  Future<String> extractText(String filePath) async {
    final ext = filePath.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return extractTextFromPDF(filePath);
      case 'docx':
        return extractTextFromDocx(filePath);
      case 'pptx':
        return extractTextFromPptx(filePath);
      default:
        throw Exception(
            'صيغة الملف غير مدعومة: .$ext (المدعوم حالياً: pdf, docx, pptx)');
    }
  }

  /// محاولة تقريبية لإضافة أسطر جديدة بين فقرات Word بالاعتماد على عناصر <w:p>
  String _insertParagraphBreaks(XmlDocument document, String fallbackText) {
    final paragraphs = document.findAllElements('p', namespace: '*');
    if (paragraphs.isEmpty) return fallbackText;

    final buffer = StringBuffer();
    for (final p in paragraphs) {
      final runsText = p.findAllElements('t', namespace: '*').map((n) => n.innerText).join();
      if (runsText.trim().isNotEmpty) {
        buffer.writeln(runsText);
      }
    }
    final result = buffer.toString().trim();
    return result.isNotEmpty ? result : fallbackText;
  }
}
