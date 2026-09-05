/// نموذج بيانات عنصر مخزَّن في أرشيف التسجيلات المحلي (SQLite)
class ArchiveItem {
  final int? id;
  final String title;
  final String subject; // بيئة، بترول، اجتماع، محاضرة...
  final String audioPath;
  final String? pdfPath;
  final String transcriptionText;
  final String summary;
  final String language; // ar, fr, en, dz أو مزيج منها
  final DateTime createdAt;

  ArchiveItem({
    this.id,
    required this.title,
    required this.subject,
    required this.audioPath,
    this.pdfPath,
    required this.transcriptionText,
    required this.summary,
    required this.language,
    required this.createdAt,
  });

  ArchiveItem copyWith({int? id}) {
    return ArchiveItem(
      id: id ?? this.id,
      title: title,
      subject: subject,
      audioPath: audioPath,
      pdfPath: pdfPath,
      transcriptionText: transcriptionText,
      summary: summary,
      language: language,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subject': subject,
      'audioPath': audioPath,
      'pdfPath': pdfPath,
      'transcriptionText': transcriptionText,
      'summary': summary,
      'language': language,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ArchiveItem.fromMap(Map<String, dynamic> map) {
    return ArchiveItem(
      id: map['id'] as int?,
      title: map['title'] as String,
      subject: map['subject'] as String,
      audioPath: map['audioPath'] as String,
      pdfPath: map['pdfPath'] as String?,
      transcriptionText: map['transcriptionText'] as String,
      summary: map['summary'] as String,
      language: map['language'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
