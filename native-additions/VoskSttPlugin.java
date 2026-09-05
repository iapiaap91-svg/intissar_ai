package com.intissarai.app;

import android.content.res.AssetManager;
import android.util.Log;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import org.json.JSONException;
import org.json.JSONObject;
import org.vosk.Model;
import org.vosk.Recognizer;
import org.vosk.android.RecognitionListener;
import org.vosk.android.SpeechService;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;

/**
 * إضافة Capacitor مخصصة: تفريغ صوتي محلي بالكامل (Offline) عبر مكتبة
 * Vosk، بديلاً عن Web Speech API (غير موجودة أصلاً داخل Android WebView،
 * وحتى لو كانت موجودة فهي تحتاج إنترنت).
 *
 * ملاحظة صراحة: هاذ الملف مكتوب يدوياً بلا اختبار ترجمة (compile) حقيقي في
 * البيئة اللي كتبته فيها — هو الجزء الأكثر عرضة لحاجة تصحيح فأول بناء
 * حقيقي عبر GitHub Actions (نفس أسلوب قراءة سجلات الأخطاء الحقيقية لي
 * استعملناه قبل مع release.yml).
 */
@CapacitorPlugin(
    name = "VoskStt",
    permissions = {
        @Permission(strings = { android.Manifest.permission.RECORD_AUDIO }, alias = "microphone")
    }
)
public class VoskSttPlugin extends Plugin implements RecognitionListener {

    private static final String TAG = "VoskSttPlugin";
    private static final HashMap<String, String> LANG_ASSET_DIR = new HashMap<String, String>() {{
        put("ar", "vosk-models/ar/model");
        put("fr", "vosk-models/fr/model");
        put("en", "vosk-models/en/model");
    }};

    private Model model;
    private SpeechService speechService;
    private String currentLang = "ar";

    @PluginMethod
    public void startListening(PluginCall call) {
        if (!getPermissionState("microphone").equals(com.getcapacitor.PermissionState.GRANTED)) {
            requestPermissionForAlias("microphone", call, "microphonePermsCallback");
            return;
        }
        doStartListening(call);
    }

    @PermissionCallback
    private void microphonePermsCallback(PluginCall call) {
        if (getPermissionState("microphone").equals(com.getcapacitor.PermissionState.GRANTED)) {
            doStartListening(call);
        } else {
            call.reject("صلاحية الميكروفون مرفوضة — خصنا الصلاحية باش يخدم التفريغ الصوتي المحلي.");
        }
    }

    private void doStartListening(PluginCall call) {
        String lang = call.getString("lang", "ar");
        try {
            stopInternal();
            String modelPath = ensureModelExtracted(lang);
            model = new Model(modelPath);
            Recognizer recognizer = new Recognizer(model, 16000.0f);
            speechService = new SpeechService(recognizer, 16000.0f);
            currentLang = lang;
            speechService.startListening(this);
            call.resolve();
        } catch (Exception e) {
            Log.e(TAG, "startListening failed", e);
            call.reject("تعذّر تشغيل التفريغ الصوتي المحلي: " + e.getMessage(), e);
        }
    }

    @PluginMethod
    public void stopListening(PluginCall call) {
        stopInternal();
        if (call != null) call.resolve();
    }

    private void stopInternal() {
        if (speechService != null) {
            speechService.stop();
            speechService.shutdown();
            speechService = null;
        }
        if (model != null) {
            model.close();
            model = null;
        }
    }

    /**
     * تفكيك ملفات النموذج من assets/ (داخل الـ APK) إلى تخزين داخلي حقيقي
     * فالمرة الأولى فقط — Vosk يحتاج مسار ملف حقيقي على القرص، ما يقدرش
     * يقرا مباشرة من داخل ملف الـ APK المضغوط.
     */
    private String ensureModelExtracted(String lang) throws IOException {
        String assetDir = LANG_ASSET_DIR.containsKey(lang) ? LANG_ASSET_DIR.get(lang) : LANG_ASSET_DIR.get("ar");
        File targetDir = new File(getContext().getFilesDir(), "vosk-extracted/" + lang + "/model");
        File doneMarker = new File(targetDir, ".extracted_ok");
        if (!doneMarker.exists()) {
            if (targetDir.exists()) deleteRecursive(targetDir);
            targetDir.mkdirs();
            copyAssetFolder(getContext().getAssets(), assetDir, targetDir);
            new FileOutputStream(doneMarker).close();
        }
        return targetDir.getAbsolutePath();
    }

    private void copyAssetFolder(AssetManager assets, String srcPath, File destDir) throws IOException {
        String[] files = assets.list(srcPath);
        if (files == null || files.length == 0) {
            // ملف وحيد (ماشي مجلد)
            copyAssetFile(assets, srcPath, new File(destDir, new File(srcPath).getName()));
            return;
        }
        destDir.mkdirs();
        for (String file : files) {
            String childAssetPath = srcPath + "/" + file;
            String[] grandchildren = assets.list(childAssetPath);
            if (grandchildren != null && grandchildren.length > 0) {
                copyAssetFolder(assets, childAssetPath, new File(destDir, file));
            } else {
                copyAssetFile(assets, childAssetPath, new File(destDir, file));
            }
        }
    }

    private void copyAssetFile(AssetManager assets, String assetPath, File destFile) throws IOException {
        try (InputStream in = assets.open(assetPath); OutputStream out = new FileOutputStream(destFile)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1) out.write(buffer, 0, read);
        }
    }

    private void deleteRecursive(File f) {
        if (f.isDirectory()) {
            File[] children = f.listFiles();
            if (children != null) for (File c : children) deleteRecursive(c);
        }
        f.delete();
    }

    // ---------- org.vosk.android.RecognitionListener ----------

    @Override
    public void onPartialResult(String hypothesis) {
        JSObject data = new JSObject();
        data.put("text", extractField(hypothesis, "partial"));
        notifyListeners("partialResult", data);
    }

    @Override
    public void onResult(String hypothesis) {
        emitFinal(hypothesis);
    }

    @Override
    public void onFinalResult(String hypothesis) {
        emitFinal(hypothesis);
    }

    private void emitFinal(String hypothesis) {
        String text = extractField(hypothesis, "text");
        if (text != null && !text.trim().isEmpty()) {
            JSObject data = new JSObject();
            data.put("text", text);
            notifyListeners("finalResult", data);
        }
    }

    @Override
    public void onError(Exception e) {
        Log.e(TAG, "Vosk recognition error", e);
        JSObject data = new JSObject();
        data.put("message", e.getMessage());
        notifyListeners("sttError", data);
    }

    @Override
    public void onTimeout() {
        // ماكاش صوت لفترة — نخليو الخدمة تكمل عادي، الواجهة تقرر واش توقف.
    }

    private String extractField(String json, String field) {
        try {
            JSONObject obj = new JSONObject(json);
            return obj.optString(field, "");
        } catch (JSONException e) {
            return "";
        }
    }
}
