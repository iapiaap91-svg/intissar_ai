# حالة مشروع Intissar AI

> هذا الملف هو الذاكرة الحقيقية الوحيدة للمشروع بين الجلسات. اقرأه أولاً
> فعلياً قبل أي استئناف — لا تفترض محتواه.

## بنية المشروع الفعلية (وليس كما وُصفت في رسائل سابقة)
- `TranscriptionResult` / `TranscriptionSegment` في `lib/models/transcription_model.dart`
  هو النموذج الحقيقي المستخدم في `HomeScreen`.
- تدفق المعالجة في `HomeScreen._processAudio`:
  1. `WhisperService.transcribeAudio` (تفريغ صوتي محلي حسب `WhisperModelType`)
  2. `DiarizationService.assignSpeakers` (فصل متحدثين)
  3. `TextCorrectionService.correct` (تصحيح لغوي)
  4. حفظ آلي غير حاجب (`unawaited`) إلى الأرشيف المشفَّر عبر `_saveToArchive`
- `CodeSwitchingParser.formatMixedLanguageText` هو الاسم الحقيقي للدالة.

## المراحل المُنجزة (تراكمياً عبر الجلسات)

### المرحلة 1 — نظام الأرشيف + الأذونات + سطح المكتب الأساسي
| المهمة | الملفات |
|---|---|
| نموذج ومخزن الأرشيف + شاشة البحث/الفلترة | `lib/models/archive_item.dart`, `lib/services/archive_database_service.dart`, `lib/screens/archive_screen.dart` |
| ربط الحفظ الآلي بعد كل تسجيل + زر الأرشيف في AppBar | `lib/screens/home_screen.dart` |
| خدمة الأذونات (مقيّدة Android/iOS) | `lib/services/permission_service.dart` |
| طلب الأذونات عند الإقلاع | `lib/main.dart` |

### المرحلة 2 — إصلاح دعم سطح المكتب الفعلي لـ Whisper
**اكتشاف حرج تم حسمه:** تحقّقتُ (بحث ويب مباشر في توثيق pub.dev) أن
`whisper_flutter_plus` تدعم Android/iOS **فقط**، فاستبدلتها بناءً على قرار
المستخدم بـ `whisper_ggml_plus` (Android/iOS/Windows/Linux/macOS، مؤكَّد من
التوثيق الرسمي). أُعيدت كتابة `lib/services/whisper_service.dart` بالكامل
مع الحفاظ على نفس الواجهة العامة (`WhisperModelType`, `isModelDownloaded`,
`downloadModel(onProgress:)`, `initializeModel`, `transcribeAudio`) —
**لم يتم لمس** `home_screen.dart` أو `model_settings_screen.dart` بسبب هذا
التبديل. فائدة جانبية: لم تعد هناك حاجة لربط `whisper.dll`/`libwhisper.so`
يدوياً — `whisper_ggml_plus` إضافة FFI حقيقية تُدرجها تلقائياً.

⚠️ **نقطة غير مؤكدة 100%**: افترضتُ وجود `WhisperModel.small` و
`WhisperModel.medium` في تعداد الحزمة (قياساً على `WhisperModel.base` و
`WhisperModel.largeV3Turbo` المؤكَّدين من التوثيق). تحقّق من هذا عبر
الإكمال التلقائي في IDE بعد `flutter pub get` (انظر `whisper_service.dart`
→ getter `packageModel`).

### المرحلة 3 — تشفير قاعدة البيانات (SQLCipher) + تحديث آلي لـ Linux + CI/CD
- **تشفير الأرشيف بالكامل (AES-256 عبر SQLCipher)**: استُبدلت `sqflite` +
  `sqflite_common_ffi` بـ `sqlite3` + `sqlcipher_flutter_libs` (تدعم فعلياً
  Android/iOS/macOS/Windows/Linux — تحقّقتُ من ذلك في توثيق pub.dev، مع
  ملاحظة أن أحدث إصدار للحزمة `0.7.0+eol` أصبح مهملاً لصالح الاعتماد على
  `sqlite3: ^3.x` مباشرة مستقبلاً؛ استخدمتُ عمداً الإصدار الأخير المستقر
  المُوثَّق جيداً `^0.6.8` تفادياً للاعتماد على API غير موثَّق بعد). مفتاح
  التشفير (256 بت) يُولَّد عشوائياً ويُخزَّن في خزنة النظام الآمنة عبر
  `flutter_secure_storage` (`lib/services/key_service.dart`) — وليس في
  الكود. أُعيدت كتابة `lib/services/archive_database_service.dart` بالكامل
  للاعتماد على `sqlite3` مباشرة (بدل الواجهة غير المتزامنة لـ `sqflite`)
  **مع الحفاظ على نفس أسماء الدوال العامة** (`insertArchive`,
  `searchArchives`, `updatePdfPath`, `deleteArchive`) — لم تتأثر
  `archive_screen.dart` ولا `home_screen.dart`.
  تفاصيل التحقق من نجاح التشفير موثّقة في `SECURITY.md`.
- `lib/main.dart`: أُزيلت تهيئة `sqflite_common_ffi` (لم تعد مستخدمة إطلاقاً).
- **تحديث تلقائي لـ Linux**: وُسِّعت `lib/services/auto_updater_service.dart`
  لتدعم Windows (كما كانت) **و**Linux عبر AppImage (بلا صلاحيات جذر،
  استبدال ذاتي عبر متغير البيئة `APPIMAGE`) بالإضافة لدالة اختيارية
  `installDebUpdateLinux` (تحتاج `pkexec`، غير مربوطة تلقائياً لأنها تتطلب
  كلمة مرور من المستخدم). `HomeScreen` تفحص التحديثات الآن على
  `Platform.isWindows || Platform.isLinux`، وتختار رابط التنزيل المناسب
  عبر `AutoUpdaterService.downloadUrlForCurrentPlatform()`.
- `version.json.example` حُدِّث ليحمل `windows_download_url` و
  `linux_appimage_url` منفصلين بدل `download_url` وحيد.
- **CI/CD كامل**: `.github/workflows/release.yml` (بناء Windows + توقيع
  رقمي اختياري مقيّد بـ `if: secrets.WIN_CERTIFICATE_BASE64 != ''` كي لا
  يفشل البناء إن لم تُضَف الأسرار + بناء Linux ينتج **كلاً من** `.tar.gz`
  و`.AppImage` (الأخير ضروري لتفعيل التحديث الآلي أعلاه))
  و`.github/workflows/security-scan.yml` (Semgrep + `flutter analyze` +
  `dart pub outdated` + CodeQL لأكواد C/C++ الأصلية — **صُحِّحت** خطوة
  CodeQL عن النسخة المُرسَلة سابقاً: بدل بناء مجلد `build_cpp/` وهمي غير
  موجود أصلاً في مشروع Flutter، تُبنى الآن عبر `flutter build linux
  --release` الحقيقي، وتُتخطى بأمان إن لم يوجد مجلد `windows/`/`linux/`
  بعد). `SECURITY.md` يوثّق خطوات Branch Protection اليدوية على واجهة
  GitHub (لا يمكن أتمتتها بملف).

### المرحلة 4 — تشغيل البناء فعلياً عبر GitHub Actions (بلا Flutter محلي)
بما أن بيئة هذه المحادثة (sandbox) لا تملك Flutter SDK ولا اتصالاً
بالإنترنت (تحقّقتُ فعلياً: لا `flutter`/`dart`، ولا وصول شبكي)، ولا يمكنها
تصريف تطبيقات Android/Windows/Linux أصلاً حتى لو توفّر Flutter (تحتاج
Android SDK/NDK، Visual Studio، GTK — أدوات نظام ثقيلة)، تقرّر البناء
الفعلي عبر GitHub Actions بدل هذه الجلسة:
- عدّلت `release.yml`: كل job (Windows/Linux/**Android الجديد**) يشغّل
  `flutter create --platforms=... .` بنفسه في بداية التشغيل، فتُولَّد
  مجلدات `windows/`, `linux/`, `android/` تلقائياً على عامل GitHub Actions
  — **لم يعد شرطاً تشغيل هذا الأمر محلياً أولاً** لكي ينجح البناء عبر CI.
- **job جديد `build-android`**: يولّد `android/`، يحقن أذونات
  `AndroidManifest.xml` المطلوبة عبر `sed` تلقائياً (ميكروفون، تخزين،
  خدمة أمامية)، ثم `flutter build apk --release` ويرفع الـ APK كمُلحق
  إصدار (Release Asset). ⚠️ **ملاحظة صريحة**: هذا الـ APK موقَّع بمفتاح
  debug الافتراضي لـ Flutter (لا يوجد keystore Release مُعدّ بعد) — صالح
  للتجربة والتوزيع المباشر (side-load) فقط، **غير كافٍ للرفع على Google
  Play** (يتطلب ذلك keystore خاص بك + إعداد `key.properties`، غير مُنفَّذ).
- `security-scan.yml`: خطوة CodeQL تولّد `linux/` بنفس الطريقة قبل البناء.

## لم يُنفَّذ بعد (يتطلب بيئة محلية فعلية)
1. `flutter pub get` — أول تحقق حقيقي من عدم وجود أخطاء ترجمة (compile)،
   خاصة أسماء `WhisperModel.small/medium` المذكورة أعلاه، وواجهة `sqlite3`/
   `Row` في `archive_database_service.dart` (لم يُتحقق من أن `Row` تدعم
   الوصول بالاسم `row['col']` بنفس الشكل المفترض — راجع بعد `pub get`).
2. `flutter create --platforms=android,windows,linux .` (لا توجد بعد
   مجلدات `android/`, `windows/`, `linux/` في المشروع محلياً — لكن
   **لم يعد هذا يمنع البناء عبر CI**: أضفتُ خطوة `flutter create
   --platforms=...` داخل كل job في `release.yml` و`security-scan.yml`
   نفسها، فتُولَّد هذه المجلدات تلقائياً على عامل GitHub Actions عند كل
   تشغيل، دون الحاجة لتشغيلها محلياً أولاً. يبقى تشغيلها محلياً مفيداً
   فقط إن أردت تطويراً/تجربة على جهازك مباشرة بدل الانتظار لدورة CI).
3. إضافة الأذونات التالية داخل `android/app/src/main/AndroidManifest.xml`
   (داخل `<manifest>`، قبل `<application>`) فور توفّر المجلد:
   ```xml
   <uses-permission android:name="android.permission.RECORD_AUDIO" />
   <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
   <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
   <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
   <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
   ```
4. تثبيت Visual Studio 2022 (C++ Desktop) على Windows، وGTK/clang/cmake/
   libssl-dev على Linux (أمر واحد موجود في المرحلة السابقة من هذا الملف
   وفي ملفات CI)، ثم اختبار تشغيل حقيقي: `flutter run -d windows` /
   `flutter run -d linux` / `flutter run` على أندرويد — **تسجيل صوتي فعلي**
   للتأكد أن `whisper_ggml_plus` يعمل، وأن قاعدة البيانات المشفَّرة تُنشأ
   وتُقرأ بلا أخطاء.
5. إعداد Branch Protection وأسرار GitHub Actions يدوياً — الخطوات كاملة
   في `SECURITY.md`.
6. اختياري: إضافة `assets/icon.png` (256×256 على الأقل) قبل تشغيل CI بناء
   AppImage في `release.yml`، وإلا يُبنى AppImage بدون أيقونة مخصّصة (لا
   يفشل البناء، فقط تحذير).

## نقطة الاستئناف الدقيقة (EXACT RESUME POINT)
1. `flutter pub get` وإصلاح أي خطأ تصريف يظهر (الأكثر احتمالاً: أسماء
   `WhisperModel` أو تفاصيل `Row` في `archive_database_service.dart`).
2. `flutter create --platforms=android,windows,linux .`
3. تحديث `AndroidManifest.xml` بالأذونات أعلاه.
4. اختبار حقيقي كامل على الأقل على منصة موبايل وواحدة من سطح المكتب:
   تسجيل → تفريغ → حفظ في الأرشيف المشفَّر → استرجاعه بالبحث.
5. دفع (`git push`) وربط أسرار GitHub Actions حسب `SECURITY.md`، ثم إنشاء
   Release أول (`v1.0.0`) للتأكد أن `release.yml` ينتج المثبّتات فعلياً.
