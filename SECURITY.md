# الأمان والحماية — Intissar AI

هذا الملف يوثّق خطوات **يدوية** على واجهة GitHub لا يمكن تفعيلها عبر ملفات
في المستودع (إعدادات Branch Protection هي إعدادات حساب/مستودع، وليست ملفات).

## 1. منع دمج أي Pull Request يحتوي ثغرات عالية الخطورة

1. افتح المستودع على GitHub → **Settings → Branches** (أو **Rules → Rulesets**).
2. **Add branch protection rule** → حدّد الفرع الرئيسي (`main` أو `master`).
3. فعّل:
   - **Require status checks to pass before merging** → ابحث عن
     `CodeQL Analysis (C/C++)` و`Flutter & Dependency Security Scan` من
     `.github/workflows/security-scan.yml` وأضفهما كشرط إجباري.
   - **Require code scanning results to be resolved before merging**
     (يتطلب GitHub Advanced Security للمستودعات الخاصة، متاح مجاناً
     للمستودعات العامة) → اختر مستوى الخطورة: **High and Critical**.

بعد هذا الإعداد، أي PR يحتوي ثغرة High/Critical يكتشفها CodeQL يظهر عليه
علامة ❌ ويُغلَق زر **Merge** تلقائياً حتى يُصلَح.

## 2. أسرار GitHub Actions اللازمة (Secrets)

اذهب إلى **Settings → Secrets and variables → Actions → New repository
secret** وأضف (اختيارية، فقط إن رغبت بالتوقيع الرقمي لمثبّت Windows):

| الاسم | القيمة |
|---|---|
| `WIN_CERTIFICATE_BASE64` | شهادة `.pfx` مُحوَّلة إلى Base64 (انظر أدناه) |
| `WIN_CERT_PASSWORD` | كلمة مرور ملف الشهادة |
| `SEMGREP_APP_TOKEN` | اختياري، فقط إن أردت لوحة تحكم Semgrep |

### تحويل شهادة `.pfx` إلى Base64 (PowerShell محلياً على Windows)
```powershell
$fileContentBytes = [System.IO.File]::ReadAllBytes("C:\path\to\your\certificate.pfx")
$base64Content = [System.Convert]::ToBase64String($fileContentBytes)
Set-Clipboard -Value $base64Content
```
الصق الناتج مباشرة كقيمة السر `WIN_CERTIFICATE_BASE64`.

> ملاحظة: خطوات التوقيع الرقمي في `.github/workflows/release.yml` مكتوبة
> بحيث تُتخطى تلقائياً وبأمان (`if: secrets.WIN_CERTIFICATE_BASE64 != ''`)
> إن لم تُضِف هذه الأسرار — لن يفشل البناء، فقط لن يُوقَّع المثبّت رقمياً.

## 3. تشفير قاعدة بيانات الأرشيف (SQLCipher)

قاعدة بيانات الأرشيف (`ArchiveDatabaseService`) مشفّرة بالكامل بخوارزمية
AES-256 عبر SQLCipher، ومفتاح التشفير مولَّد عشوائياً (256 بت) عند أول
تشغيل ومخزَّن في خزنة النظام الآمنة (`KeyService` عبر
`flutter_secure_storage`) — **وليس** داخل الكود أو ملف نصي عادي.

### التحقق من نجاح التشفير بعد أول تشغيل فعلي على جهاز حقيقي
- حاول فتح ملف قاعدة البيانات (داخل مجلد بيانات التطبيق، اسمه
  `intissar_ai_archive.db`) ببرنامج مثل **DB Browser for SQLite** دون
  إدخال كلمة مرور — يجب أن تظهر رسالة: *"File is encrypted or is not a
  database"*.
- بمحرر نصي سداسي عشري (Hex Editor)، يجب أن تكون محتويات الملف بيانات
  عشوائية معماة بالكامل، دون أي نص واضح (Plaintext).

### متطلبات نظام إضافية عند البناء (وليس وقت التشغيل عند المستخدم النهائي)
- **Linux**: `sudo apt install libssl-dev` (مُضافة بالفعل في
  `security-scan.yml` و`release.yml`).
- **Windows**: `choco install openssl` إن واجهت خطأ بناء متعلقاً بـ OpenSSL.
