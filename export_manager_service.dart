import 'dart:io';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:arabic_reshaper/arabic_reshaper.dart';

/// مدير التصدير والتحميل — يولّد PDF منسقاً باللغة العربية بشكل صحيح بصرياً،
/// ويصدّر الملف الصوتي الأصلي.
///
/// ملاحظة تقنية مهمة: مكتبة `pdf` الخام لا "تشكّل" الحروف العربية تلقائياً
/// (لا تحوّل الحرف المنفصل إلى شكله المتصل حسب موقعه في الكلمة)، فتظهر
/// النصوص العربية مبعثرة بدون معالجة إضافية. لهذا نمرر كل نص عربي عبر
/// `arabic_reshaper` قبل رسمه، ونحتاج أيضاً إلى **خط عربي حقيقي** (وليس
/// خط pdf الافتراضي) — راجع README لخطوة تحميل الخط المطلوبة.
class ExportManagerService {
  Future<String> generateAndSavePDF({
    required String title,
    required String fullTranscription,
    required String summary,
  }) async {
    final pdf = pw.Document();

    // تحميل خط عربي حقيقي من أصول التطبيق (يجب وضعه يدوياً — راجع README)
    final ByteData fontData = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
    final arabicFont = pw.Font.ttf(fontData);

    final reshapedTitle = ArabicReshaper.instance.reshape(title);
    final reshapedSummary = ArabicReshaper.instance.reshape(summary);
    final reshapedTranscription = ArabicReshaper.instance.reshape(fullTranscription);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFont),
        build: (pw.Context context) {
          return [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Header(
                    level: 0,
                    child: pw.Text('Intissar AI - IAP Hassi Messaoud',
                        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text('العنوان: $reshapedTitle',
                      style: pw.TextStyle(font: arabicFont, fontSize: 16)),
                  pw.Divider(),
                  pw.SizedBox(height: 10),
                  pw.Text('الملخص التنفيذي:',
                      style: pw.TextStyle(
                          font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text(reshapedSummary, style: pw.TextStyle(font: arabicFont)),
                  pw.SizedBox(height: 15),
                  pw.Text('النص التفريغي الكامل:',
                      style: pw.TextStyle(
                          font: arabicFont, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text(reshapedTranscription, style: pw.TextStyle(font: arabicFont)),
                ],
              ),
            ),
          ];
        },
      ),
    );

    final outputDir = await getApplicationDocumentsDirectory();
    final safeTitle = title.replaceAll(RegExp(r'\s+'), '_');
    final savePath = p.join(outputDir.path, '${safeTitle}_Export.pdf');
    final file = File(savePath);
    await file.writeAsBytes(await pdf.save());

    return savePath;
  }

  /// إتاحة تحميل الملف الصوتي الأصلي إلى مجلد قابل للوصول من خارج التطبيق
  Future<String> exportAudioFile(String originalAudioPath) async {
    final sourceFile = File(originalAudioPath);
    if (!await sourceFile.exists()) {
      throw Exception('ملف الصوت الأصلي غير موجود');
    }

    final downloadsDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final newPath = p.join(downloadsDir.path, p.basename(originalAudioPath));

    await sourceFile.copy(newPath);
    return newPath;
  }
}
