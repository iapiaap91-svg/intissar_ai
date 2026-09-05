import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/archive_item.dart';
import '../services/archive_database_service.dart';
import 'quiz_screen.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({Key? key}) : super(key: key);

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final ArchiveDatabaseService _dbService = ArchiveDatabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<ArchiveItem> _items = [];
  bool _isLoading = true;

  String _selectedSubject = 'الكل';
  String _selectedLanguage = 'الكل';

  final List<String> _subjects = const [
    'الكل',
    'محاضرات عامة',
    'اجتماعات عمل',
    'الهندسة والتكرير',
    'البيئة والمناخ',
  ];
  final List<String> _languages = const [
    'الكل',
    'ar/dz/fr',
    'العربية/الدارجة',
    'الفرنسية',
    'الإنجليزية',
  ];

  @override
  void initState() {
    super.initState();
    _fetchArchives();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _fetchArchives() async {
    setState(() => _isLoading = true);
    final results = await _dbService.searchArchives(
      searchQuery: _searchController.text,
      selectedSubject: _selectedSubject,
      selectedLanguage: _selectedLanguage,
    );
    if (!mounted) return;
    setState(() {
      _items = results;
      _isLoading = false;
    });
  }

  Future<void> _confirmDelete(ArchiveItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف التسجيل'),
        content: Text('هل تريد حذف "${item.title}" نهائياً من الأرشيف؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && item.id != null) {
      await _dbService.deleteArchive(item.id!);
      _fetchArchives();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('أرشيف التسجيلات والدروس'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'بحث في عنوان أو نص المحاضرات...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => _fetchArchives(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedSubject,
                        decoration: const InputDecoration(labelText: 'التخصص'),
                        items: _subjects
                            .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          setState(() => _selectedSubject = val!);
                          _fetchArchives();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedLanguage,
                        decoration: const InputDecoration(labelText: 'اللغة'),
                        items: _languages
                            .map((l) => DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          setState(() => _selectedLanguage = val!);
                          _fetchArchives();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('لا توجد تسجيلات مطابقة للبحث'))
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${item.subject} • ${DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt)}\n${item.summary}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.quiz, color: Colors.indigo),
                                    tooltip: 'اختبار وتصدير',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => QuizScreen(
                                            lessonText: item.transcriptionText,
                                            audioPath: item.audioPath,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    tooltip: 'حذف',
                                    onPressed: () => _confirmDelete(item),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
