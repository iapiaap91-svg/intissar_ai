import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import '../models/archive_item.dart';
import 'key_service.dart';

/// خدمة تخزين واسترجاع وبحث سجلات الأرشيف محلياً عبر قاعدة بيانات SQLite
/// **مشفّرة بالكامل** بخوارزمية AES-256 عبر SQLCipher (حزمة
/// `sqlcipher_flutter_libs` + `sqlite3`)، ومفتاح التشفير مخزَّن في خزنة
/// النظام الآمنة عبر [KeyService] وليس داخل الكود أو ملف عادي.
///
/// تعمل هذه الخدمة على أندرويد وiOS وmacOS وWindows وLinux (نفس حزمة
/// `sqlcipher_flutter_libs` تدعم الخمسة). على Linux/Windows يتطلب النظام
/// وجود OpenSSL وقت البناء فقط (مُجمَّع ثابتاً داخل الحزمة الناتجة، ليس
/// مطلوباً من المستخدم النهائي).
class ArchiveDatabaseService {
  static Database? _db;
  static bool _androidOverrideApplied = false;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    // على أندرويد فقط: يجب إخبار حزمة sqlite3 صراحةً بفتح مكتبة SQLCipher
    // الأصلية بدلاً من sqlite3 العادية غير المشفَّرة.
    if (Platform.isAndroid && !_androidOverrideApplied) {
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
      _androidOverrideApplied = true;
    }

    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final dbPath = p.join(dir.path, 'intissar_ai_archive.db');

    final encryptionKey = await KeyService.getOrCreateKey();

    final db = sqlite3.open(dbPath);

    // تفعيل التشفير فوراً — يجب أن يكون أول أمر يُنفَّذ على الاتصال قبل
    // أي قراءة أو كتابة، وإلا سيُعامَل الملف كقاعدة بيانات عادية غير مشفَّرة.
    db.execute("PRAGMA key = '$encryptionKey';");

    db.execute('''
      CREATE TABLE IF NOT EXISTS archives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        subject TEXT NOT NULL,
        audioPath TEXT NOT NULL,
        pdfPath TEXT,
        transcriptionText TEXT NOT NULL,
        summary TEXT NOT NULL,
        language TEXT NOT NULL,
        createdAt TEXT NOT NULL
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_archives_subject ON archives(subject);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_archives_language ON archives(language);');

    return db;
  }

  ArchiveItem _rowToItem(Row row) {
    return ArchiveItem(
      id: row['id'] as int?,
      title: row['title'] as String,
      subject: row['subject'] as String,
      audioPath: row['audioPath'] as String,
      pdfPath: row['pdfPath'] as String?,
      transcriptionText: row['transcriptionText'] as String,
      summary: row['summary'] as String,
      language: row['language'] as String,
      createdAt: DateTime.parse(row['createdAt'] as String),
    );
  }

  /// حفظ تسجيل جديد في الأرشيف، يعيد المعرف (id) الجديد
  Future<int> insertArchive(ArchiveItem item) async {
    final db = await _database;
    db.execute(
      '''
      INSERT INTO archives
        (title, subject, audioPath, pdfPath, transcriptionText, summary, language, createdAt)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        item.title,
        item.subject,
        item.audioPath,
        item.pdfPath,
        item.transcriptionText,
        item.summary,
        item.language,
        item.createdAt.toIso8601String(),
      ],
    );
    return db.lastInsertRowId;
  }

  /// تحديث مسار ملف PDF بعد التصدير (مثلاً بعد استخدام ExportManagerService)
  Future<int> updatePdfPath(int id, String pdfPath) async {
    final db = await _database;
    db.execute(
      'UPDATE archives SET pdfPath = ? WHERE id = ?',
      [pdfPath, id],
    );
    return db.updatedRows;
  }

  /// البحث المتقدم والفلترة حسب الكلمة المفتاحية، الموضوع، واللغة
  Future<List<ArchiveItem>> searchArchives({
    String? searchQuery,
    String? selectedSubject,
    String? selectedLanguage,
  }) async {
    final db = await _database;
    final List<String> whereClauses = [];
    final List<Object?> whereArgs = [];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      whereClauses.add('(title LIKE ? OR transcriptionText LIKE ? OR summary LIKE ?)');
      whereArgs.addAll(['%$searchQuery%', '%$searchQuery%', '%$searchQuery%']);
    }

    if (selectedSubject != null && selectedSubject != 'الكل') {
      whereClauses.add('subject = ?');
      whereArgs.add(selectedSubject);
    }

    if (selectedLanguage != null && selectedLanguage != 'الكل') {
      whereClauses.add('language = ?');
      whereArgs.add(selectedLanguage);
    }

    final whereString = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    final ResultSet result = db.select(
      'SELECT * FROM archives $whereString ORDER BY createdAt DESC',
      whereArgs,
    );

    return result.map(_rowToItem).toList();
  }

  /// حذف تسجيل من الأرشيف
  Future<int> deleteArchive(int id) async {
    final db = await _database;
    db.execute('DELETE FROM archives WHERE id = ?', [id]);
    return db.updatedRows;
  }
}
