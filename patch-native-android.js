/**
 * يخدم بعد `npx cap add android` (لي يولّد مجلد android/ من الصفر فكل
 * بناء) — يزرع فيه إضافة Vosk المخصصة، ويربطها فـ MainActivity، ويضيف
 * صلاحية الميكروفون، ويضيف تبعية مكتبة vosk-android لـ Gradle.
 *
 * هذا التصميم (بدل تضمين مجلد android/ جاهز فالمستودع) مقصود: مجلد
 * android/ لكابسيتور فيه مئات الملفات المولَّدة تلقائياً، والاعتماد على
 * الأداة الرسمية لتوليده فكل مرة أوثق بزاف من الاحتفاظ بنسخة يدوية قد
 * تتعارض مع تحديثات Capacitor لاحقاً.
 */
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const ANDROID_APP = path.join(ROOT, "android", "app");
const PKG_DIR = path.join(ANDROID_APP, "src", "main", "java", "com", "intissarai", "app");
const NATIVE_SRC = path.join(ROOT, "native-additions");

function fail(msg){ console.error("❌ " + msg); process.exit(1); }

if (!fs.existsSync(path.join(ROOT, "android"))) {
  fail("مجلد android/ ماكاش — خصك تديري `npx cap add android` قبل هاذ السكريبت.");
}

// 1) نسخ VoskSttPlugin.java و MainActivity.java الجديدة
fs.mkdirSync(PKG_DIR, { recursive: true });
fs.copyFileSync(path.join(NATIVE_SRC, "VoskSttPlugin.java"), path.join(PKG_DIR, "VoskSttPlugin.java"));
fs.copyFileSync(path.join(NATIVE_SRC, "MainActivity.java"), path.join(PKG_DIR, "MainActivity.java"));
console.log("✅ VoskSttPlugin.java و MainActivity.java اتزرعو.");

// 2) صلاحية الميكروفون فـ AndroidManifest.xml
const manifestPath = path.join(ANDROID_APP, "src", "main", "AndroidManifest.xml");
let manifest = fs.readFileSync(manifestPath, "utf8");
if (!manifest.includes("android.permission.RECORD_AUDIO")) {
  manifest = manifest.replace(
    "<manifest ",
    "<!-- أُضيفت لدعم Vosk (تفريغ صوتي محلي) -->\n<manifest "
  ).replace(
    /<\/manifest>/,
    ''
  );
  // إدراج صلاحية قبل وسم <application
  manifest = manifest.replace(
    /<application/,
    '<uses-permission android:name="android.permission.RECORD_AUDIO" />\n\n    <application'
  );
  fs.writeFileSync(manifestPath, manifest);
  console.log("✅ صلاحية RECORD_AUDIO اتزادت فـ AndroidManifest.xml.");
} else {
  console.log("صلاحية RECORD_AUDIO موجودة مسبقاً.");
}

// 3) تبعية vosk-android فـ android/app/build.gradle
const gradlePath = path.join(ANDROID_APP, "build.gradle");
let gradle = fs.readFileSync(gradlePath, "utf8");
const voskDep = "implementation 'com.alphacephei:vosk-android:0.3.45'";
if (!gradle.includes("vosk-android")) {
  gradle = gradle.replace(
    /dependencies\s*\{/,
    "dependencies {\n    " + voskDep
  );
  fs.writeFileSync(gradlePath, gradle);
  console.log("✅ تبعية vosk-android اتزادت فـ android/app/build.gradle.");
} else {
  console.log("تبعية vosk-android موجودة مسبقاً.");
}

// 4) التأكد أن mavenCentral() مفعّلة (فيها vosk-android) فالمستوى الجذري
const rootGradlePath = path.join(ROOT, "android", "build.gradle");
if (fs.existsSync(rootGradlePath)) {
  let rootGradle = fs.readFileSync(rootGradlePath, "utf8");
  if (!rootGradle.includes("mavenCentral()")) {
    console.warn("⚠️ mavenCentral() ما لقيناهاش فـ android/build.gradle — vosk-android قد ما يتلقاش. أضيفيها يدوياً إذا صار خطأ.");
  }
}

console.log("\n✅ انتهى تصحيح مشروع Android الأصلي (native patch).");
