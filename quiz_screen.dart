import 'package:flutter/material.dart';
import '../services/quiz_generator_service.dart';
import '../services/export_manager_service.dart';
import '../services/local_rag_service.dart';

class QuizScreen extends StatefulWidget {
  final String lessonText;
  final String audioPath;

  const QuizScreen({
    Key? key,
    required this.lessonText,
    required this.audioPath,
  }) : super(key: key);

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final QuizGeneratorService _quizService = QuizGeneratorService();
  final ExportManagerService _exportService = ExportManagerService();
  final LocalRAGService _ragService = LocalRAGService();
  final TextEditingController _questionController = TextEditingController();

  List<QuizQuestion> _questions = [];
  final Map<String, int> _selectedAnswers = {};
  bool _isLoadingQuiz = true;
  bool _isAnswering = false;
  String? _statusMessage;
  String? _ragAnswer;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    final questions = await _quizService.generateQuizFromContent(widget.lessonText);
    setState(() {
      _questions = questions;
      _isLoadingQuiz = false;
    });
  }

  Future<void> _askRAGQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _isAnswering = true;
      _ragAnswer = null;
    });

    final result = await _ragService.answerQuestion(
      question: question,
      lessonContext: widget.lessonText,
    );

    setState(() {
      _ragAnswer = result.answerText;
      _isAnswering = false;
    });
  }

  void _selectAnswer(QuizQuestion question, int selectedIndex) {
    final isCorrect = _quizService.evaluateAnswer(question, selectedIndex);
    setState(() {
      _selectedAnswers[question.id] = selectedIndex;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isCorrect ? Colors.green : Colors.red,
        content: Text(isCorrect ? '✅ إجابة صحيحة! ${question.explanation}' : '❌ إجابة خاطئة. ${question.explanation}'),
      ),
    );
  }

  Future<void> _exportPDF() async {
    try {
      final path = await _exportService.generateAndSavePDF(
        title: 'محاضرة Intissar AI',
        fullTranscription: widget.lessonText,
        summary: 'تفريغ ومراجعة تفاعلية تم توليدها محلياً على الجهاز.',
      );
      setState(() => _statusMessage = 'تم حفظ ملف الـ PDF بنجاح في: $path');
    } catch (e) {
      setState(() => _statusMessage = 'فشل تصدير PDF: $e');
    }
  }

  Future<void> _downloadAudio() async {
    try {
      final path = await _exportService.exportAudioFile(widget.audioPath);
      setState(() => _statusMessage = 'تم تحميل الصوت الأصلي في: $path');
    } catch (e) {
      setState(() => _statusMessage = 'فشل تصدير الصوت: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الاختبارات والأسئلة والتصدير')),
      body: _isLoadingQuiz
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _questionController,
                          decoration: const InputDecoration(
                            hintText: 'اطرح سؤالاً حول محتوى الدرس...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _isAnswering ? null : _askRAGQuestion,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                  if (_isAnswering) const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
                  if (_ragAnswer != null) Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_ragAnswer!),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _exportPDF,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('تحميل PDF'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _downloadAudio,
                        icon: const Icon(Icons.download_for_offline),
                        label: const Text('تحميل الصوت'),
                      ),
                    ],
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(_statusMessage!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('أسئلة الاختبار (مولّدة من محتوى الدرس):',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (_questions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'تعذّر توليد أسئلة — النص المرتبط بهذا الدرس قصير جداً أو غير متنوع بما يكفي لاستخراج مصطلحات مناسبة.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _questions.length,
                      itemBuilder: (context, index) {
                        final q = _questions[index];
                        final selected = _selectedAnswers[q.id];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${index + 1}. ${q.questionText}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                ...List.generate(q.options.length, (i) {
                                  final isSelected = selected == i;
                                  final isCorrectOption = i == q.correctOptionIndex;
                                  Color? tileColor;
                                  if (selected != null) {
                                    if (isCorrectOption) tileColor = Colors.green.shade100;
                                    else if (isSelected) tileColor = Colors.red.shade100;
                                  }
                                  return ListTile(
                                    tileColor: tileColor,
                                    title: Text(q.options[i]),
                                    leading: Icon(isSelected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked),
                                    onTap: selected == null ? () => _selectAnswer(q, i) : null,
                                  );
                                }),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
