import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// إدارة مفتاح تشفير قاعدة بيانات الأرشيف (SQLCipher / AES-256).
/// يُخزَّن المفتاح في خزنة النظام الآمنة: Android Keystore، iOS Keychain،
/// Windows Credential Manager، أو Linux Secret Service (libsecret) —
/// حسب المنصة، تلقائياً عبر `flutter_secure_storage`.
class KeyService {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'intissar_ai_db_encryption_key';

  /// الحصول على المفتاح الحالي أو توليد مفتاح عشوائي بقوة 256 بت عند أول
  /// تشغيل للتطبيق، ثم إعادة استخدامه في كل مرة لاحقة.
  static Future<String> getOrCreateKey() async {
    String? key = await _storage.read(key: _keyName);
    if (key == null) {
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      key = base64Url.encode(values);
      await _storage.write(key: _keyName, value: key);
    }
    return key;
  }
}
