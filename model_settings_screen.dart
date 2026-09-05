import 'package:flutter/material.dart';
import '../services/whisper_service.dart';

class ModelSettingsScreen extends StatefulWidget {
  final WhisperService whisperService;
  final WhisperModelType selectedModel;
  final ValueChanged<WhisperModelType> onModelSelected;

  const ModelSettingsScreen({
    Key? key,
    required this.whisperService,
    required this.selectedModel,
    required this.onModelSelected,
  }) : super(key: key);

  @override
  State<ModelSettingsScreen> createState() => _ModelSettingsScreenState();
}

class _ModelSettingsScreenState extends State<ModelSettingsScreen> {
  final Map<WhisperModelType, bool> _downloaded = {};
  final Map<WhisperModelType, double?> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _checkDownloadedModels();
  }

  Future<void> _checkDownloadedModels() async {
    for (final type in WhisperModelType.values) {
      final exists = await widget.whisperService.isModelDownloaded(type);
      if (mounted) setState(() => _downloaded[type] = exists);
    }
  }

  Future<void> _downloadModel(WhisperModelType type) async {
    setState(() => _downloadProgress[type] = 0);
    try {
      await widget.whisperService.downloadModel(
        type,
        onProgress: (p) => setState(() => _downloadProgress[type] = p),
      );
      setState(() {
        _downloaded[type] = true;
        _downloadProgress[type] = null;
      });
    } catch (e) {
      setState(() => _downloadProgress[type] = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التنزيل: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختيار نموذج التفريغ الصوتي')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: WhisperModelType.values.length,
        itemBuilder: (context, index) {
          final type = WhisperModelType.values[index];
          final isDownloaded = _downloaded[type] ?? false;
          final progress = _downloadProgress[type];
          final isSelected = widget.selectedModel == type;

          return Card(
            color: isSelected ? Colors.blue.shade50 : null,
            child: ListTile(
              title: Text(type.label, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الحجم التقريبي: ~${type.approxSizeMB} ميجابايت'),
                  if (progress != null) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: progress),
                    Text('${(progress * 100).toStringAsFixed(0)}%'),
                  ],
                ],
              ),
              trailing: isDownloaded
                  ? Radio<WhisperModelType>(
                      value: type,
                      groupValue: widget.selectedModel,
                      onChanged: (v) {
                        if (v != null) widget.onModelSelected(v);
                        setState(() {});
                      },
                    )
                  : ElevatedButton(
                      onPressed: progress == null ? () => _downloadModel(type) : null,
                      child: const Text('تنزيل'),
                    ),
            ),
          );
        },
      ),
    );
  }
}
