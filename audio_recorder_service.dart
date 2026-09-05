import 'dart:io';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// خدمة التسجيل الصوتي المحلي بالكامل (لا اتصال بالإنترنت مطلوب)
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentFilePath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get currentFilePath => _currentFilePath;

  /// طلب صلاحية الميكروفون قبل البدء
  Future<bool> _ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// بدء تسجيل جديد وحفظه في مجلد المستندات المحلي للجهاز
  Future<void> startRecording() async {
    final hasPermission = await _ensurePermission();
    if (!hasPermission) {
      throw Exception('لم يتم منح صلاحية استخدام الميكروفون');
    }

    if (_isRecording) return;

    final docDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(docDir.path, 'recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(recordingsDir.path, 'rec_$timestamp.wav');

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000, // معدل العينة المتوافق مع Whisper.cpp
        numChannels: 1,
      ),
      path: filePath,
    );

    _currentFilePath = filePath;
    _isRecording = true;
  }

  /// إيقاف التسجيل الحالي وإرجاع مسار الملف الصوتي الناتج
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    final path = await _recorder.stop();
    _isRecording = false;
    _currentFilePath = null;
    return path;
  }

  /// إلغاء التسجيل الحالي دون حفظ
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    await _recorder.cancel();
    _isRecording = false;
    _currentFilePath = null;
  }

  void dispose() {
    _recorder.dispose();
  }
}
