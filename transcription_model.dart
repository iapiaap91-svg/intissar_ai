class TranscriptionSegment {
  final String text;
  final Duration start;
  final Duration end;
  final String speaker;
  final String language;

  TranscriptionSegment({
    required this.text,
    required this.start,
    required this.end,
    this.speaker = 'Speaker 1',
    this.language = 'auto',
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'start_ms': start.inMilliseconds,
        'end_ms': end.inMilliseconds,
        'speaker': speaker,
        'language': language,
      };

  factory TranscriptionSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptionSegment(
      text: json['text'] as String,
      start: Duration(milliseconds: json['start_ms'] as int),
      end: Duration(milliseconds: json['end_ms'] as int),
      speaker: json['speaker'] as String? ?? 'Speaker 1',
      language: json['language'] as String? ?? 'auto',
    );
  }
}

class TranscriptionResult {
  final String fullText;
  final List<TranscriptionSegment> segments;
  final String audioFilePath;
  final DateTime createdAt;

  TranscriptionResult({
    required this.fullText,
    required this.segments,
    required this.audioFilePath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'full_text': fullText,
        'segments': segments.map((s) => s.toJson()).toList(),
        'audio_file_path': audioFilePath,
        'created_at': createdAt.toIso8601String(),
      };

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    return TranscriptionResult(
      fullText: json['full_text'] as String,
      segments: (json['segments'] as List)
          .map((s) => TranscriptionSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
      audioFilePath: json['audio_file_path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
