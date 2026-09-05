import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/audio_recorder_service.dart';
import '../services/whisper_service.dart';
import '../services/text_correction_service.dart';
import '../services/diarization_service.dart';
import '../services/code_switching_parser.dart';
import '../services/archive_database_service.dart';
import '../services/auto_updater_service.dart';
import '../models/transcription_model.dart';
import '../models/archive_item.dart';
import 'archive_screen.dart';
import 'document_import_screen.dart';
import 'model_settings_screen.dart';
import 'quiz_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioRecorderService _recorderService = AudioRecorderService();
  final WhisperService _whisperService = WhisperService();
  final TextCorrectionService _correctionService = TextCorrectionService();
  final DiarizationService _diarizationService = DiarizationService();
  final ArchiveDatabaseService _archiveDbService = ArchiveDatabaseService();

  bool _isProcessing = false;
  String _processingLabel = '';
  TranscriptionResult? _result;
  WhisperModelType _selectedModel = WhisperModelType.base;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux) {
      unawaited(_checkAppUpdates());
    }
  }

  @override
  void dispose() {
    _recorderService.dispose();
    super.dispose();
  }

  /// فحص وجود إصدار Windows جديد وعرض حوار تحديث اختياري (لا يعطّل
  /// استخدام التطبيق إن رفض المستخدم أو تعذّر الاتصال بالسيرفر).
  Future<void> _checkAppUpdates() async {
    final updateData = await AutoUpdaterService.checkForUpdates();
    if (updateData == null || !mounted) return;

    final downloadUrl = AutoUpdaterService.downloadUrlForCurrentPlatform(updateData);
    if (downloadUrl == null) return; // لا يوجد رابط تنزيل مخصص لهذه المنصة

    double progress = 0.0;
    bool downloading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('تحديث جديد متوفر (v${updateData['version']})'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(updateData['release_notes'] as String? ??
                      'يتضمن هذا التحديث تحسينات في السرعة واستقرار النماذج.'),
                  const SizedBox(height: 15),
                  if (downloading) ...[
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                    Text('جاري التنزيل والتثبيت... ${(progress * 100).toStringAsFixed(0)}%'),
                  ],
                ],
              ),
              actions: [
                if (!downloading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('تأجيل'),
                  ),
                if (!downloading)
                  ElevatedButton(
                    onPressed: () {
                      setDialogState(() => downloading = true);
                      AutoUpdaterService.downloadAndInstallUpdate(
                        downloadUrl,
                        (p) => setDialogState(() => progress = p),
                      );
                    },
                    child: const Text('تحديث الآن'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleRecording() async {
    if (_recorderService.isRecording) {
      final path = await _recorderService.stopRecording();
      setState(() {});
      if (path != null) {
        _processAudio(path);
      }
    } else {
      try {
        await _recorderService.startRecording();
        setState(() {});
      } catch (e) {
        _showError('تعذّر بدء التسجيل: $e');
      }
    }
  }

  Future<void> _processAudio(String path) async {
    setState(() {
      _isProcessing = true;
      _processingLabel = 'جاري تحويل الصوت إلى نص محلياً...';
    });

    try {
      // 1. التفريغ الصوتي عبر Whisper المحلي
      final rawResult = await _whisperService.transcribeAudio(
        path,
        modelType: _selectedModel,
      );

      // 2. فصل المتحدثين (Phase 2)
      setState(() => _processingLabel = 'جاري تحديد المتحدثين...');
      final diarizedSegments = await _diarizationService.assignSpeakers(
        path,
        rawResult.segments,
      );

      // 3. التصحيح اللغوي (Phase 2)
      setState(() => _processingLabel = 'جاري التصحيح اللغوي للنص...');
      final correctedSegments = diarizedSegments
          .map((seg) => TranscriptionSegment(
                text: _correctionService.correct(seg.text, language: seg.language),
                start: seg.start,
                end: seg.end,
                speaker: seg.speaker,
                language: seg.language,
              ))
          .toList();

      final correctedFullText = _correctionService.correct(rawResult.fullText);

      final finalResult = TranscriptionResult(
        fullText: correctedFullText,
        segments: correctedSegments,
        audioFilePath: rawResult.audioFilePath,
        createdAt: rawResult.createdAt,
      );

      setState(() {
        _result = finalResult;
        _isProcessing = false;
      });

      // 4. الحفظ الآلي في الأرشيف المحلي (SQLite) دون انتظار من المستخدم
      unawaited(_saveToArchive(finalResult));
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('خطأ في تحويل الصوت: $e');
    }
  }

  /// حفظ نتيجة التفريغ تلقائياً في قاعدة بيانات الأرشيف بمجرد اكتمال
  /// المعالجة (التفريغ + فصل المتحدثين + التصحيح اللغوي).
  Future<void> _saveToArchive(TranscriptionResult result) async {
    try {
      final formattedText = CodeSwitchingParser.formatMixedLanguageText(result.fullText);
      final now = result.createdAt;
      final autoTitle =
          'تسجيل ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final autoSummary =
          formattedText.length > 120 ? '${formattedText.substring(0, 120)}...' : formattedText;

      final archiveItem = ArchiveItem(
        title: autoTitle,
        subject: 'محاضرات عامة',
        audioPath: result.audioFilePath,
        transcriptionText: formattedText,
        summary: autoSummary,
        language: 'ar/dz/fr',
        createdAt: now,
      );

      await _archiveDbService.insertArchive(archiveItem);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ الآلي في الأرشيف بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('تعذّر الحفظ في الأرشيف: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Intissar AI - IAP Hassi Messaoud'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'الأرشيف',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArchiveScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_suggest),
            tooltip: 'اختيار نموذج التفريغ الصوتي',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ModelSettingsScreen(
                    whisperService: _whisperService,
                    selectedModel: _selectedModel,
                    onModelSelected: (m) => setState(() => _selectedModel = m),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'استيراد مستند أو صورة',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DocumentImportScreen()),
              );
            },
          ),
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.quiz),
              tooltip: 'اختبار وتصدير هذا التفريغ',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QuizScreen(
                      lessonText: _result!.fullText,
                      audioPath: _result!.audioFilePath,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Icon(
                      _recorderService.isRecording ? Icons.mic : Icons.mic_none,
                      size: 64,
                      color: _recorderService.isRecording ? Colors.red : Colors.blue,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _recorderService.isRecording
                          ? 'جاري التسجيل المحلي...'
                          : 'اضغط للبدء في تسجيل المحاضرة أو الاجتماع',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 15),
                    ElevatedButton(
                      onPressed: _isProcessing ? null : _toggleRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _recorderService.isRecording ? Colors.red : Colors.blue,
                      ),
                      child: Text(_recorderService.isRecording ? 'إيقاف التسجيل' : 'بدء التسجيل'),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isProcessing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              Text(_processingLabel),
            ],
            if (_result != null && !_isProcessing) ...[
              const Align(
                alignment: Alignment.centerRight,
                child: Text('النص التفريغي المفصل:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    itemCount: _result!.segments.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final seg = _result!.segments[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seg.speaker,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: seg.speaker == 'Speaker 1' ? Colors.blue : Colors.deepOrange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(seg.text),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
