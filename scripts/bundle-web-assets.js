/**
 * تجهيز نسخة GitHub Pages من التطبيق.
 * لا يحمل نماذج Vosk الضخمة؛ تلك خاصة بـ APK.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const https = require("https");

const ROOT = path.join(__dirname, "..");
const LIBS_DIR = path.join(ROOT, "www", "libs");
const TESSDATA_DIR = path.join(LIBS_DIR, "tessdata");

function ensureDir(p){ fs.mkdirSync(p, {recursive:true}); }

function copyFile(src, dest){
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
}

function download(url, dest){
  return new Promise((resolve, reject) => {
    ensureDir(path.dirname(dest));
    const file = fs.createWriteStream(dest);
    https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location){
        file.close();
        return download(res.headers.location, dest).then(resolve, reject);
      }
      if (res.statusCode !== 200){
        file.close();
        fs.unlink(dest, () => {});
        reject(new Error("HTTP " + res.statusCode + " for " + url));
        return;
      }
      res.pipe(file);
      file.on("finish", () => file.close(() => resolve(dest)));
    }).on("error", (err) => {
      file.close();
      fs.unlink(dest, () => {});
      reject(err);
    });
  });
}

async function main(){
  ensureDir(LIBS_DIR);
  ensureDir(TESSDATA_DIR);

  copyFile(
    path.join(ROOT, "node_modules", "tesseract.js", "dist", "tesseract.min.js"),
    path.join(LIBS_DIR, "tesseract.min.js")
  );
  copyFile(
    path.join(ROOT, "node_modules", "tesseract.js", "dist", "worker.min.js"),
    path.join(LIBS_DIR, "tesseract-worker.min.js")
  );

  const core = path.join(ROOT, "node_modules", "tesseract.js-core");
  if (fs.existsSync(core)){
    for (const f of fs.readdirSync(core)){
      if (f.endsWith(".js") || f.endsWith(".wasm")){
        copyFile(path.join(core, f), path.join(LIBS_DIR, "tesseract-core", f));
      }
    }
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

  const base = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/";
  for (const lang of ["ara","fra","eng"]){
    await download(base + lang + ".traineddata",
      path.join(TESSDATA_DIR, lang + ".traineddata"));
  }

  const htmlPath = path.join(ROOT, "www", "index.html");
  const html = fs.readFileSync(htmlPath, "utf8");
  const badRemote = (html.match(/https?:\/\/[^\s"')]+/g) || [])
    .filter(u => ![
      "generativelanguage.googleapis.com",
      "api.anthropic.com",
      "api.openai.com"
    ].some(a => u.includes(a)));

  if (badRemote.length){
    console.error("Unexpected runtime URLs:");
    badRemote.forEach(x => console.error(" - " + x));
    process.exit(1);
  }

  console.log("✅ Web assets bundled. GitHub Pages can serve ./www offline for the browser-local features.");
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
