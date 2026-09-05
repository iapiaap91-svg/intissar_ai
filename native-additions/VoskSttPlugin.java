package com.intissarai.app;

import android.Manifest;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
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

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.util.HashMap;

/**
 * Native offline STT + WAV recorder.
 * One AudioRecord stream feeds Vosk and the exact same PCM stream is saved as WAV.
 * This avoids opening the microphone twice (the old MediaRecorder + Vosk setup
 * could result in silent recordings on Android devices).
 */
@CapacitorPlugin(
    name = "VoskStt",
    permissions = {
        @Permission(strings = {Manifest.permission.RECORD_AUDIO}, alias = "microphone")
    }
)
public class VoskSttPlugin extends Plugin {
    private static final String TAG = "VoskSttPlugin";
    private static final int SAMPLE_RATE = 16000;
    private static final short CHANNELS = 1;
    private static final short BITS_PER_SAMPLE = 16;

    private static final HashMap<String, String> LANG_ASSET_DIR = new HashMap<String, String>() {{
        put("ar", "vosk-models/ar/model");
        put("fr", "vosk-models/fr/model");
        put("en", "vosk-models/en/model");
    }};

    private volatile boolean recording = false;
    private volatile String lastError = null;
    private Thread workerThread;
    private AudioRecord audioRecord;
    private Model model;
    private Recognizer recognizer;
    private File currentWavFile;
    private long pcmBytesWritten = 0;
    private long startedAt = 0;

    @PluginMethod
    public void startListening(PluginCall call) {
        if (!getPermissionState("microphone").equals(com.getcapacitor.PermissionState.GRANTED)) {
            requestPermissionForAlias("microphone", call, "microphonePermsCallback");
            return;
        }
        doStart(call);
    }

    @PermissionCallback
    private void microphonePermsCallback(PluginCall call) {
        if (getPermissionState("microphone").equals(com.getcapacitor.PermissionState.GRANTED)) {
            doStart(call);
        } else {
            call.reject("صلاحية الميكروفون مرفوضة — خصنا الصلاحية باش يخدم التسجيل والتفريغ المحلي.");
        }
    }

    private synchronized void doStart(PluginCall call) {
        lastError = null;
        if (recording) {
            call.reject("التسجيل راهو شغال أصلاً.");
            return;
        }

        String lang = call.getString("lang", "ar");
        try {
            stopInternal();

            String modelPath = ensureModelExtracted(lang);
            model = new Model(modelPath);
            recognizer = new Recognizer(model, SAMPLE_RATE);

            int minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            );
            if (minBuffer <= 0) minBuffer = SAMPLE_RATE * 2;
            int bufferSize = Math.max(minBuffer * 2, 4096);

            audioRecord = new AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            );

            if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                throw new IOException("تعذر تهيئة AudioRecord.");
            }

            currentWavFile = new File(getContext().getFilesDir(), "recordings");
            if (!currentWavFile.exists() && !currentWavFile.mkdirs()) {
                throw new IOException("تعذر إنشاء مجلد التسجيلات.");
            }
            currentWavFile = new File(currentWavFile, "intissar-" + System.currentTimeMillis() + ".wav");
            pcmBytesWritten = 0;
            startedAt = System.currentTimeMillis();

            writeWavHeader(currentWavFile, 0);
            audioRecord.startRecording();
            recording = true;

            final int finalBufferSize = bufferSize;
            workerThread = new Thread(() -> recordLoop(finalBufferSize), "Intissar-Vosk-Recorder");
            workerThread.start();
            call.resolve();
        } catch (Exception e) {
            Log.e(TAG, "start failed", e);
            stopInternal();
            call.reject("تعذر تشغيل التسجيل المحلي: " + (e.getMessage() == null ? "خطأ غير معروف" : e.getMessage()), e);
        }
    }

    @PluginMethod
    public synchronized void stopListening(PluginCall call) {
        if (!recording) {
            JSObject result = new JSObject();
            if (currentWavFile != null && currentWavFile.exists()) {
                result.put("path", currentWavFile.getAbsolutePath());
                result.put("mimeType", "audio/wav");
            }
            if (call != null) call.resolve(result);
            return;
        }

        recording = false;
        try {
            if (audioRecord != null) audioRecord.stop();
        } catch (Exception ignored) {}

        if (workerThread != null) {
            try { workerThread.join(3000); } catch (InterruptedException ignored) {}
        }
        workerThread = null;

        try { if (audioRecord != null) audioRecord.release(); } catch (Exception ignored) {}
        audioRecord = null;

        try { if (recognizer != null) recognizer.close(); } catch (Exception ignored) {}
        recognizer = null;
        try { if (model != null) model.close(); } catch (Exception ignored) {}
        model = null;

        try { writeWavHeader(currentWavFile, pcmBytesWritten); } catch (Exception e) { Log.e(TAG, "WAV finalize failed", e); }

        JSObject result = new JSObject();
        if (currentWavFile != null && currentWavFile.exists()) {
            result.put("path", currentWavFile.getAbsolutePath());
            result.put("mimeType", "audio/wav");
            result.put("size", currentWavFile.length());
            result.put("durationMs", Math.max(0, System.currentTimeMillis() - startedAt));
        }
        if (call != null) call.resolve(result);
    }

    private void recordLoop(int bufferSize) {
        byte[] buffer = new byte[bufferSize];
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(currentWavFile, true);
            while (recording && audioRecord != null) {
                int read = audioRecord.read(buffer, 0, buffer.length);
                if (read <= 0) continue;

                out.write(buffer, 0, read);
                pcmBytesWritten += read;

                if (recognizer != null) {
                    boolean done = recognizer.acceptWaveForm(buffer, read);
                    if (done) {
                        emitResult(recognizer.getResult(), false);
                    } else {
                        emitPartial(recognizer.getPartialResult());
                    }
                }
            }

            if (recognizer != null) {
                emitResult(recognizer.getFinalResult(), true);
            }
        } catch (Exception e) {
            Log.e(TAG, "record loop failed", e);
            JSObject data = new JSObject();
            lastError = e.getMessage() == null ? "خطأ في التسجيل/التفريغ" : e.getMessage();
            data.put("message", lastError);
            notifyListeners("sttError", data);
        } finally {
            if (out != null) {
                try { out.flush(); out.close(); } catch (IOException ignored) {}
            }
        }
    }

    private void emitPartial(String json) {
        String text = extractField(json, "partial");
        if (text == null || text.trim().isEmpty()) return;
        JSObject data = new JSObject();
        data.put("text", text);
        notifyListeners("partialResult", data);
    }

    private void emitResult(String json, boolean finalResult) {
        String text = extractField(json, "text");
        if (text == null || text.trim().isEmpty()) return;
        JSObject data = new JSObject();
        data.put("text", text);
        notifyListeners("finalResult", data);
    }

    private String extractField(String json, String field) {
        try {
            JSONObject obj = new JSONObject(json);
            return obj.optString(field, "");
        } catch (JSONException e) {
            return "";
        }
    }

    private synchronized void stopInternal() {
        recording = false;
        try { if (audioRecord != null) audioRecord.stop(); } catch (Exception ignored) {}
        if (workerThread != null) {
            try { workerThread.join(1000); } catch (InterruptedException ignored) {}
            workerThread = null;
        }
        try { if (audioRecord != null) audioRecord.release(); } catch (Exception ignored) {}
        audioRecord = null;
        try { if (recognizer != null) recognizer.close(); } catch (Exception ignored) {}
        recognizer = null;
        try { if (model != null) model.close(); } catch (Exception ignored) {}
        model = null;
    }

    private String ensureModelExtracted(String lang) throws IOException {
        String assetDir = LANG_ASSET_DIR.containsKey(lang) ? LANG_ASSET_DIR.get(lang) : LANG_ASSET_DIR.get("ar");
        File targetDir = new File(getContext().getFilesDir(), "vosk-extracted/" + lang + "/model");
        File doneMarker = new File(targetDir, ".extracted_ok");
        if (!doneMarker.exists()) {
            if (targetDir.exists()) deleteRecursive(targetDir);
            if (!targetDir.mkdirs() && !targetDir.exists()) throw new IOException("تعذر إنشاء مجلد النموذج.");
            copyAssetFolder(getContext().getAssets(), assetDir, targetDir);
            new FileOutputStream(doneMarker).close();
        }
        return targetDir.getAbsolutePath();
    }

    private void copyAssetFolder(android.content.res.AssetManager assets, String srcPath, File destDir) throws IOException {
        String[] files = assets.list(srcPath);
        if (files == null || files.length == 0) {
            copyAssetFile(assets, srcPath, new File(destDir, new File(srcPath).getName()));
            return;
        }
        if (!destDir.exists() && !destDir.mkdirs()) throw new IOException("تعذر إنشاء مجلد الأصول.");
        for (String file : files) {
            String child = srcPath + "/" + file;
            String[] nested = assets.list(child);
            if (nested != null && nested.length > 0) copyAssetFolder(assets, child, new File(destDir, file));
            else copyAssetFile(assets, child, new File(destDir, file));
        }
    }

    private void copyAssetFile(android.content.res.AssetManager assets, String assetPath, File destFile) throws IOException {
        File parent = destFile.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) throw new IOException("تعذر إنشاء مجلد الملف.");
        try (InputStream in = assets.open(assetPath); FileOutputStream out = new FileOutputStream(destFile)) {
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

    private void writeWavHeader(File file, long pcmLength) throws IOException {
        if (file == null) return;
        if (!file.exists()) return;
        RandomAccessFile raf = new RandomAccessFile(file, "rw");
        try {
            raf.seek(0);
            raf.writeBytes("RIFF");
            writeLEInt(raf, (int)Math.min(0xFFFFFFFFL, 36 + pcmLength));
            raf.writeBytes("WAVE");
            raf.writeBytes("fmt ");
            writeLEInt(raf, 16);
            writeLEShort(raf, (short)1);
            writeLEShort(raf, CHANNELS);
            writeLEInt(raf, SAMPLE_RATE);
            int byteRate = SAMPLE_RATE * CHANNELS * BITS_PER_SAMPLE / 8;
            writeLEInt(raf, byteRate);
            short blockAlign = (short)(CHANNELS * BITS_PER_SAMPLE / 8);
            writeLEShort(raf, blockAlign);
            writeLEShort(raf, BITS_PER_SAMPLE);
            raf.writeBytes("data");
            writeLEInt(raf, (int)Math.min(0xFFFFFFFFL, pcmLength));
        } finally {
            raf.close();
        }
    }

    private void writeLEInt(RandomAccessFile raf, int value) throws IOException {
        raf.write(value & 0xff); raf.write((value >> 8) & 0xff); raf.write((value >> 16) & 0xff); raf.write((value >> 24) & 0xff);
    }

    private void writeLEShort(RandomAccessFile raf, short value) throws IOException {
        raf.write(value & 0xff); raf.write((value >> 8) & 0xff);
    }
}
