import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/document_parser_service.dart';
import '../services/vision_ocr_service.dart';
import '../services/code_switching_parser.dart';
import 'quiz_screen.dart';

/// شاشة استيراد المستندات (PDF/Word/PowerPoint) وتحليل الصور (OCR)
class DocumentImportScreen extends StatefulWidget {
  const DocumentImportScreen({Key? key}) : super(key: key);

  @override
  State<DocumentImportScreen> createState() => _DocumentImportScreenState();
}

class _DocumentImportScreenState extends State<DocumentImportScreen> {
  final DocumentParserService _documentParser = DocumentParserService();
  final VisionOCRService _ocrService = VisionOCRService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = false;
  String _extractedText = '';
  String _statusMessage = '';

  Future<void> _pickAndParseDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'pptx'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري استخراج النص من المستند...';
      _extractedText = '';
    });

    try {
      final path = result.files.single.path!;
      final rawText = await _documentParser.extractText(path);
      final formattedText = CodeSwitchingParser.formatMixedLanguageText(rawText);
      setState(() {
        _extractedText = formattedText;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
      _showError('تعذّر استخراج نص المستند: $e');
    }
  }

  Future<void> _pickAndAnalyzeImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري تحليل الصورة (OCR)...';
      _extractedText = '';
    });

    try {
      final rawText = await _ocrService.extractTextFromImage(image.path);
      final formattedText = CodeSwitchingParser.formatMixedLanguageText(rawText);
      setState(() {
        _extractedText = formattedText.isEmpty
            ? 'لم يتم التعرّف على أي نص واضح في الصورة.'
            : formattedText;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
      _showError('تعذّر تحليل الصورة: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد مستند أو صورة')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _pickAndParseDocument,
                    icon: const Icon(Icons.description),
                    label: const Text('استيراد PDF / Word / PPTX'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _pickAndAnalyzeImage,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('تصوير سؤال / سبورة'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              Text(_statusMessage),
            ],
            if (_extractedText.isNotEmpty && !_isLoading) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => QuizScreen(
                          lessonText: _extractedText,
                          audioPath: '',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.quiz),
                  label: const Text('توليد اختبار وطرح أسئلة من هذا المحتوى'),
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(_extractedText),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
