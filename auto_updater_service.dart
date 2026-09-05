import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// فحص وتنزيل وتثبيت التحديثات التلقائية لنسخ سطح المكتب: **Windows**
/// (مثبّت Inno Setup .exe بوضع صامت) و**Linux** (حزمة AppImage محمولة، أو
/// حزمة .deb عبر pkexec لمن يفضّلها).
///
/// ملاحظة: لا تُستدعى أي دالة من هذه الخدمة على أندرويد/iOS — تحديث
/// المتاجر (Google Play / App Store) يخضع لآلياتها الخاصة وليس لهذه
/// الخدمة، وتُستدعى الدوال هنا من `HomeScreen` بشرط `Platform.isWindows`
/// أو `Platform.isLinux` فقط.
///
/// شكل `version.json` المتوقع على السيرفر (يدعم منصتين في نفس الملف):
/// ```json
/// {
///   "version": "1.0.1",
///   "release_notes": "...",
///   "windows_download_url": "https://.../IntissarAI_Windows_Setup_v1.0.1.exe",
///   "linux_appimage_url": "https://.../IntissarAI-x86_64.AppImage"
/// }
/// ```
class AutoUpdaterService {
  // رابط فحص التحديثات (ملف JSON على GitHub Releases أو سيرفر خاص)
  static const String _updateUrl =
      'https://raw.githubusercontent.com/your-org/intissar_ai/main/version.json';

  /// فحص وجود تحديث جديد مقارنة بالإصدار الحالي المُثبَّت (Windows/Linux فقط)
  static Future<Map<String, dynamic>?> checkForUpdates() async {
    if (!(Platform.isWindows || Platform.isLinux)) return null;
    try {
      final response = await http.get(Uri.parse(_updateUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final latestVersion = data['version'] as String;

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        if (_isNewerVersion(currentVersion, latestVersion)) {
          return data;
        }
      }
    } catch (e) {
      // فشل الفحص (بلا اتصال مثلاً) لا يجب أن يوقف تشغيل التطبيق
      // ignore: avoid_print
      print('خطأ أثناء فحص التحديثات: $e');
    }
    return null;
  }

  /// رابط التنزيل المناسب للمنصة الحالية من بيانات `version.json`، أو null
  /// إن لم يوفّر السيرفر رابطاً لهذه المنصة.
  static String? downloadUrlForCurrentPlatform(Map<String, dynamic> updateData) {
    if (Platform.isWindows) {
      return updateData['windows_download_url'] as String? ?? updateData['download_url'] as String?;
    }
    if (Platform.isLinux) {
      return updateData['linux_appimage_url'] as String?;
    }
    return null;
  }

  /// نقطة الدخول الموحّدة: تنزيل وتثبيت التحديث حسب المنصة الحالية تلقائياً.
  static Future<void> downloadAndInstallUpdate(
    String downloadUrl,
    void Function(double progress) onProgress,
  ) async {
    if (Platform.isWindows) {
      await _downloadAndInstallWindows(downloadUrl, onProgress);
    } else if (Platform.isLinux) {
      await _downloadAndInstallLinuxAppImage(downloadUrl, onProgress);
    } else {
      throw UnsupportedError('التحديث الآلي مدعوم على Windows وLinux فقط حالياً');
    }
  }

  /// [Windows] تنزيل مثبّت Inno Setup الجديد وتشغيله تلقائياً بوضع صامت،
  /// ثم إغلاق التطبيق الحالي لتمكين المثبت من استبدال الملفات.
  static Future<void> _downloadAndInstallWindows(
    String downloadUrl,
    void Function(double progress) onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final setupFilePath = p.join(tempDir.path, 'Update_Installer.exe');

    await _downloadWithProgress(downloadUrl, setupFilePath, onProgress);

    // /SILENT: يعرض شريط التقدم بدون أسئلة إضافية
    // /CLOSEAPPLICATIONS و /RESTARTAPPLICATIONS: يغلق التطبيق الحالي
    // تلقائياً ويعيد تشغيله بعد التثبيت
    await Process.start(
      setupFilePath,
      ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  /// [Linux / AppImage] تنزيل نسخة AppImage جديدة، منحها صلاحية التنفيذ،
  /// واستبدال الملف الحالي بها ثم إعادة تشغيل التطبيق. لا يحتاج صلاحيات
  /// جذر (root) لأن AppImage يعمل بالكامل في مساحة المستخدم.
  static Future<void> _downloadAndInstallLinuxAppImage(
    String downloadUrl,
    void Function(double progress) onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final newAppImagePath = p.join(tempDir.path, 'intissar_ai_new.AppImage');

    await _downloadWithProgress(downloadUrl, newAppImagePath, onProgress);

    // منح صلاحيات التنفيذ (Execution Permissions)
    await Process.run('chmod', ['+x', newAppImagePath]);

    // متغيّر البيئة APPIMAGE يوفّره وقت التشغيل الفعلي لملف AppImage الحالي
    final currentAppPath = Platform.environment['APPIMAGE'];

    if (currentAppPath != null) {
      await File(newAppImagePath).copy(currentAppPath);
      await Process.start(currentAppPath, [], mode: ProcessStartMode.detached);
    } else {
      // التطبيق لا يعمل حالياً من داخل AppImage رسمي (مثال: أثناء التطوير)
      await Process.start(newAppImagePath, [], mode: ProcessStartMode.detached);
    }

    exit(0);
  }

  /// [Linux / .deb] تثبيت تحديث عبر حزمة .deb باستخدام `pkexec` لعرض نافذة
  /// كلمة مرور المسؤول الرسومية. **يتطلب تفاعلاً من المستخدم** (كلمة
  /// المرور)، لذا لا يُستدعى تلقائياً في الخلفية — مخصص لزر تحديث يدوي
  /// إن اختار المستخدم توزيع .deb بدلاً من AppImage.
  static Future<void> installDebUpdateLinux(String downloadUrl) async {
    if (!Platform.isLinux) {
      throw UnsupportedError('تحديث .deb متاح على Linux فقط');
    }
    final tempDir = await getTemporaryDirectory();
    final debFilePath = p.join(tempDir.path, 'update.deb');

    final response = await http.get(Uri.parse(downloadUrl));
    await File(debFilePath).writeAsBytes(response.bodyBytes);

    await Process.start(
      'pkexec',
      ['dpkg', '-i', debFilePath],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  static Future<void> _downloadWithProgress(
    String downloadUrl,
    String destinationPath,
    void Function(double progress) onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(downloadUrl));
    final response = await http.Client().send(request);

    final contentLength = response.contentLength ?? 0;
    int downloaded = 0;

    final file = File(destinationPath);
    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      downloaded += chunk.length;
      sink.add(chunk);
      if (contentLength > 0) {
        onProgress(downloaded / contentLength);
      }
    }
    await sink.close();
  }

  static bool _isNewerVersion(String current, String latest) {
    final currParts = current.split('.').map(int.tryParse).map((v) => v ?? 0).toList();
    final lateParts = latest.split('.').map(int.tryParse).map((v) => v ?? 0).toList();
    final length = currParts.length > lateParts.length ? currParts.length : lateParts.length;

    for (int i = 0; i < length; i++) {
      final c = i < currParts.length ? currParts[i] : 0;
      final l = i < lateParts.length ? lateParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}
