import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// إدارة أذونات الميكروفون والتخزين، وإعفاء التطبيق من تحسين البطارية
/// (Battery Optimization) على أندرويد لضمان استمرار التسجيل في الخلفية
/// أثناء الجلسات الطويلة. لا تُستدعى هذه الأذونات على سطح المكتب.
class PermissionService {
  /// طلب جميع الأذونات الأساسية اللازمة للتشغيل المباشر (أندرويد/iOS فقط)
  static Future<bool> requestInitialPermissions() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      // على Windows/Linux/macOS لا حاجة لطلب أذونات وقت التشغيل
      return true;
    }

    final statuses = await [
      Permission.microphone,
      Permission.storage,
      if (Platform.isAndroid) Permission.manageExternalStorage,
    ].request();

    return statuses[Permission.microphone]?.isGranted ?? false;
  }

  /// طلب إيقاف تحسين البطارية لضمان استمرار التسجيل الصوتي دون إغلاق
  /// التطبيق في الخلفية (أندرويد فقط)
  static Future<void> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// التحقق من صلاحيات الميكروفون
  static Future<bool> hasMicrophonePermission() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return true;
    return await Permission.microphone.isGranted;
  }
}
