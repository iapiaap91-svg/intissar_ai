/**
 * سكريبت يخدم فـ GitHub Actions (فيه إنترنت) قبل بناء APK — يجمع كل
 * المكتبات ونماذج اللغة محلياً باش التطبيق النهائي يخدم Offline 100%.
 *
 * ملاحظة صريحة: هاذ السكريبت ما يقدرش يخدم فبيئة Claude (sandbox) لأنها
 * بلا إنترنت أصلاً — هذا بالضبط سبب وجوده كخطوة منفصلة تخدم فـ CI.
 *
 * يدير:
 *  1. نسخ ملفات tesseract.js / pdfjs-dist / mammoth / jszip من
 *     node_modules إلى www/libs/ (بدل الاعتماد على CDN وقت التشغيل).
 *  2. تحميل بيانات لغة Tesseract (ara/fra/eng.traineddata) من مستودع
 *     tessdata_fast الرسمي إلى www/libs/tessdata/.
 *  3. تحميل نماذج Vosk (عربي/فرنسي/إنجليزي) من manifest models/vosk-models.json
 *     إلى android/app/src/main/assets/vosk-models/<lang>/ باش تنضم لداخل الـ APK.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const https = require("https");
const { execSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const LIBS_DIR = path.join(ROOT, "www", "libs");
const TESSDATA_DIR = path.join(LIBS_DIR, "tessdata");
const VOSK_ASSETS_DIR = path.join(ROOT, "android", "app", "src", "main", "assets", "vosk-models");

function ensureDir(p){ fs.mkdirSync(p, { recursive: true }); }

function copyFile(src, dest){
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
  console.log("copied:", path.relative(ROOT, dest));
}

function download(url, dest){
  return new Promise((resolve, reject) => {
    ensureDir(path.dirname(dest));
    const file = fs.createWriteStream(dest);
    https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        file.close();
        return download(res.headers.location, dest).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        reject(new Error("HTTP " + res.statusCode + " for " + url));
        return;
      }
      res.pipe(file);
      file.on("finish", () => file.close(() => resolve(dest)));
    }).on("error", (err) => { fs.unlink(dest, () => {}); reject(err); });
  });
}

async function step1_copyJsLibs(){
  console.log("\n== 1) نسخ مكتبات JS محلياً ==");
  ensureDir(LIBS_DIR);

  copyFile(
    path.join(ROOT, "node_modules", "tesseract.js", "dist", "tesseract.min.js"),
    path.join(LIBS_DIR, "tesseract.min.js")
  );
  copyFile(
    path.join(ROOT, "node_modules", "tesseract.js", "dist", "worker.min.js"),
    path.join(LIBS_DIR, "tesseract-worker.min.js")
  );

  // tesseract.js-core: ملفات الـ WASM (تُثبَّت تلقائياً كـ dependency فرعية
  // لـ tesseract.js). ننسخ المجلد كامل باش createWorker يلقى كل البدائل
  // (simd / non-simd / lstm-only) بلا ما نخمّن اسم ملف واحد بالضبط.
  const coreSrcDir = path.join(ROOT, "node_modules", "tesseract.js-core");
  if (fs.existsSync(coreSrcDir)) {
    ensureDir(path.join(LIBS_DIR, "tesseract-core"));
    for (const f of fs.readdirSync(coreSrcDir)) {
      if (f.endsWith(".wasm") || f.endsWith(".js")) {
        copyFile(path.join(coreSrcDir, f), path.join(LIBS_DIR, "tesseract-core", f));
      }
    }
  } else {
    console.warn("⚠️ tesseract.js-core ما لقيناهش فـ node_modules — تأكدي أنه تثبت (dependency فرعية لـ tesseract.js).");
  }

  copyFile(
    path.join(ROOT, "node_modules", "pdfjs-dist", "legacy", "build", "pdf.min.js"),
    path.join(LIBS_DIR, "pdf.min.js")
  );
  copyFile(
    path.join(ROOT, "node_modules", "pdfjs-dist", "legacy", "build", "pdf.worker.min.js"),
    path.join(LIBS_DIR, "pdf.worker.min.js")
  );
  copyFile(
    path.join(ROOT, "node_modules", "mammoth", "mammoth.browser.min.js"),
    path.join(LIBS_DIR, "mammoth.browser.min.js")
  );
  copyFile(
    path.join(ROOT, "node_modules", "jszip", "dist", "jszip.min.js"),
    path.join(LIBS_DIR, "jszip.min.js")
  );
}

async function step2_downloadTessdata(){
  console.log("\n== 2) تحميل بيانات لغة Tesseract (ara/fra/eng) ==");
  ensureDir(TESSDATA_DIR);
  const base = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/";
  const langs = ["ara", "fra", "eng"];
  for (const lang of langs) {
    const dest = path.join(TESSDATA_DIR, lang + ".traineddata");
    if (fs.existsSync(dest)) { console.log("موجود مسبقاً:", lang); continue; }
    console.log("جارٍ تحميل:", lang + ".traineddata ...");
    await download(base + lang + ".traineddata", dest);
    console.log("تم:", lang);
  }
}

async function step3_downloadVoskModels(){
  console.log("\n== 3) تحميل نماذج Vosk (STT محلي) ==");
  const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, "models", "vosk-models.json"), "utf8"));
  ensureDir(VOSK_ASSETS_DIR);

  for (const m of manifest.models) {
    const langDir = path.join(VOSK_ASSETS_DIR, m.lang);
    const modelDir = path.join(langDir, "model");
    if (fs.existsSync(modelDir)) {
      console.log("موجود مسبقاً:", m.lang);
      continue;
    }
    const zipPath = path.join(langDir, m.name + ".zip");
    console.log("جارٍ تحميل نموذج " + m.lang + " (~" + m.approxSizeMB + "MB) ...");
    await download(m.url, zipPath);
    execSync(`unzip -q "${zipPath}" -d "${langDir}"`);
    fs.renameSync(path.join(langDir, m.name), modelDir);
    fs.unlinkSync(zipPath);
    console.log("تم:", m.lang);
  }
}

async function step4_verifyNoRemoteUrls(){
  console.log("\n== 4) التحقق النهائي: بحث عن أي https:// متبقية فـ www/index.html ==");
  const html = fs.readFileSync(path.join(ROOT, "www", "index.html"), "utf8");
  const matches = html.match(/https?:\/\/[^\s"')]+/g) || [];
  const allowedOnline = [
    "generativelanguage.googleapis.com",
    "api.anthropic.com",
    "api.openai.com"
  ];
  const unexpected = matches.filter(u => !allowedOnline.some(a => u.includes(a)));
  if (unexpected.length){
    console.error("⚠️ لقينا روابط خارجية غير متوقعة (خصها تتصلح يدوياً):");
    unexpected.forEach(u => console.error("  -", u));
    process.exitCode = 1;
  } else {
    console.log("✅ ماكاش روابط خارجية غير متوقعة. الروابط المتبقية (اختيارية Ask/Quiz فقط):");
    matches.forEach(u => console.log("  -", u));
  }
}

(async () => {
  try {
    await step1_copyJsLibs();
    await step2_downloadTessdata();
    await step3_downloadVoskModels();
    await step4_verifyNoRemoteUrls();
    console.log("\n✅ تم تجهيز كل الأصول الأوفلاين.");
  } catch (err) {
    console.error("\n❌ صار خطأ أثناء تجهيز الأصول:", err);
    process.exit(1);
  }
})();
