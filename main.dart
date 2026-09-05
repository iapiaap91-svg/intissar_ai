import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/home_screen.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ملاحظة: لم تعد هناك حاجة لتهيئة sqflite_common_ffi هنا — قاعدة بيانات
  // الأرشيف أصبحت تعتمد على sqlite3 + sqlcipher_flutter_libs (مشفّرة
  // AES-256 عبر SQLCipher) في ArchiveDatabaseService، وهي تعمل مباشرة على
  // كل من الموبايل وسطح المكتب دون تهيئة إضافية هنا.

  // طلب أذونات الميكروفون والتخزين وإعفاء البطارية قبل تشغيل الواجهات
  // (تُتجاهل تلقائياً على سطح المكتب داخل PermissionService).
  await PermissionService.requestInitialPermissions();
  await PermissionService.requestBatteryOptimizationExemption();

  runApp(const IntissarAiApp());
}

class IntissarAiApp extends StatelessWidget {
  const IntissarAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Intissar AI',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0D47A1),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      // فرض اتجاه RTL بشكل صريح بغض النظر عن لغة نظام الجهاز، لأن التطبيق
      // عربي المحتوى بالدرجة الأولى (لا نعتمد فقط على `locale` أعلاه لأن
      // بعض الأجهزة تتجاهله دون حزمة flutter_localizations وقائمة اللغات
      // المدعومة المذكورة أعلاه).
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const HomeScreen(),
    );
  }
}
