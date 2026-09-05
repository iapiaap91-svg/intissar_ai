import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';
import '../models/transcription_model.dart';

/// النماذج المدعومة، مع رابط تنزيل مباشر من مستودع ggerganov/whisper.cpp
/// على Hugging Face وحجمها التقريبي (نسخة مكممة q5_0 حيث متوفرة).
///
/// ملاحظة صريحة حول الأرقام: هذه تقديرات تقريبية شائعة لأحجام النماذج
/// المكممة، وليست مقاسة من نسخة بعينها — تحقق من الحجم الفعلي بعد التنزيل.
enum WhisperModelType {
  base(
    fileName: 'ggml-base.bin',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
    approxSizeMB: 142,
    label: 'أساسي (Base) — الأسرع، دقة متوسطة',
  ),
  small(
    fileName: 'ggml-small-q5_1.bin',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin',
    approxSizeMB: 190,
    label: 'صغير (Small) — توازن جيد',
  ),
  medium(
    fileName: 'ggml-medium-q5_0.bin',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin',
    approxSizeMB: 514,
    label: 'متوسط (Medium) — دقة عالية للدارجة والفرنسية، أبطأ',
  ),
  largeV3Turbo(
    fileName: 'ggml-large-v3-turbo-q5_0.bin',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin',
    approxSizeMB: 547,
    label: 'كبير-Turbo — أعلى دقة، يتطلب هاتفاً قوياً',
  );

  final String fileName;
  final String downloadUrl;
  final int approxSizeMB;
  final String label;

  const WhisperModelType({
    required this.fileName,
    required this.downloadUrl,
    required this.approxSizeMB,
    required this.label,
  });

  /// تحويل نوع النموذج الخاص بالتطبيق إلى تعداد الحزمة whisper_ggml_plus.
  /// ملاحظة: WhisperModel.small وWhisperModel.medium يُفترض وجودهما ضمن
  /// حزمة whisper_ggml_plus (أحجام whisper.cpp القياسية: tiny/base/small/
  /// medium/large)، لكن لم يُتحقق من ذلك بالتصريف الفعلي (compile) في هذه
  /// البيئة لعدم توفر Flutter SDK هنا. تحقق من الإكمال التلقائي (autocomplete)
  /// في IDE بعد `flutter pub get` وعدّل الأسماء إن اختلفت.
  WhisperModel get packageModel {
    switch (this) {
      case WhisperModelType.base:
        return WhisperModel.base;
      case WhisperModelType.small:
        return WhisperModel.small;
      case WhisperModelType.medium:
        return WhisperModel.medium;
      case WhisperModelType.largeV3Turbo:
        return WhisperModel.largeV3Turbo;
    }
  }
}

/// خدمة Whisper مع دعم تبديل النماذج والتنزيل عند الطلب (وليس تضمينها في
/// الـ APK) — لأن نماذج medium/large تتجاوز 500 ميجابايت، وتضمينها كأصل
/// ثابت يضخّم حجم التطبيق بشكل غير مقبول لجميع المستخدمين حتى من لا
/// يحتاج هذه الدقة.
///
/// تعمل هذه الخدمة الآن عبر `whisper_ggml_plus` (بدلاً من
/// `whisper_flutter_plus` السابقة) لأنها الحزمة التي تدعم فعلياً أندرويد
/// وiOS وأيضاً Windows وLinux وmacOS، وهو شرط أساسي لدعم سطح المكتب.
///
/// نحتفظ بمنطق التنزيل المخصص (تنزيل مباشر من HuggingFace مع تقرير تقدّم
/// حي) لكن نكتب الملف الناتج في المسار الذي تتوقعه الحزمة نفسها
/// (`WhisperController.getPath`) بدلاً من مجلد مخصص بنا، حتى تتعرف الحزمة
/// على الملف عند التفريغ الصوتي.
class WhisperService {
  final WhisperController _controller = WhisperController();
  WhisperModelType? _loadedModelType;

  WhisperModelType? get loadedModelType => _loadedModelType;

  Future<String> _modelPath(WhisperModelType type) {
    return _controller.getPath(type.packageModel);
  }

  /// التحقق مما إذا كان النموذج محمَّلاً بالفعل على الجهاز
  Future<bool> isModelDownloaded(WhisperModelType type) async {
    final path = await _modelPath(type);
    return File(path).exists();
  }

  /// تنزيل نموذج عند الطلب مع تقرير تقدم حي عبر onProgress (0.0 إلى 1.0)
  Future<void> downloadModel(
    WhisperModelType type, {
    void Function(double progress)? onProgress,
  }) async {
    final path = await _modelPath(type);
    final file = File(path);
    if (await file.exists()) return;
    await file.parent.create(recursive: true);

    final request = http.Request('GET', Uri.parse(type.downloadUrl));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception(
          'فشل تنزيل النموذج (رمز الحالة: ${response.statusCode}). تحقق من الاتصال بالإنترنت.');
    }

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    final sink = file.openWrite();

    await response.stream.map((chunk) {
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(receivedBytes / totalBytes);
      }
      return chunk;
    }).pipe(sink);

    await sink.close();
  }

  /// التحقق من جاهزية نموذج معيّن ومطابقته للتحميل الحالي (لأغراض واجهة
  /// المستخدم فقط — whisper_ggml_plus يحمّل النموذج داخلياً عند كل نداء
  /// transcribe ولا يتطلب تهيئة صريحة منفصلة كما في الحزمة السابقة).
  Future<void> initializeModel(WhisperModelType type) async {
    final isDownloaded = await isModelDownloaded(type);
    if (!isDownloaded) {
      throw Exception(
          'النموذج "${type.label}" غير محمَّل على الجهاز. نزّله أولاً عبر downloadModel().');
    }
    _loadedModelType = type;
  }

  /// تحويل الصوت إلى نص باستخدام النموذج المحمَّل حالياً (أو base افتراضياً)
  Future<TranscriptionResult> transcribeAudio(
    String audioPath, {
    WhisperModelType modelType = WhisperModelType.base,
  }) async {
    await initializeModel(modelType);

    final result = await _controller.transcribe(
      model: modelType.packageModel,
      audioPath: audioPath,
      lang: 'auto',
      withTimestamps: true,
    );

    final String rawResponse = result?.transcription.text ?? '';

    final List<TranscriptionSegment> segments = [
      TranscriptionSegment(
        text: rawResponse,
        start: Duration.zero,
        end: const Duration(seconds: 0),
        language: 'mixed_dz',
      )
    ];

    return TranscriptionResult(
      fullText: rawResponse,
      segments: segments,
      audioFilePath: audioPath,
      createdAt: DateTime.now(),
    );
  }
}
