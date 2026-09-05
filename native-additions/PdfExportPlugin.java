package com.intissarai.app;

import android.content.ContentValues;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.pdf.PdfDocument;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.text.TextDirectionHeuristics;
import android.util.Log;


import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.OutputStream;

@CapacitorPlugin(name = "PdfExport")
public class PdfExportPlugin extends Plugin {
    private static final String TAG = "PdfExportPlugin";
    private static final int PAGE_W = 595;
    private static final int PAGE_H = 842;
    private static final int MARGIN = 42;

    @PluginMethod
    public void createPdf(PluginCall call) {
        String title = call.getString("title", "انتصار AI");
        String text = call.getString("text", "");
        String date = call.getString("date", "");
        if (text == null) text = "";

        PdfDocument document = new PdfDocument();
        try {
            TextPaint tp = new TextPaint(Paint.ANTI_ALIAS_FLAG);
            tp.setColor(Color.rgb(22, 38, 43));
            tp.setTextSize(15);
            tp.setTypeface(Typeface.create("sans", Typeface.NORMAL));

            int contentW = PAGE_W - (MARGIN * 2);
            int contentTop = MARGIN + 68;
            int contentH = PAGE_H - contentTop - MARGIN;
            // ملاحظة: StaticLayout ماعندهاش constructor مباشر ياخذ
            // TextDirectionHeuristic (هذا سبب خطأ الترجمة السابق) — الطريقة
            // الصحيحة منذ Android 6.0 (API 23) هي StaticLayout.Builder.
            StaticLayout layout = StaticLayout.Builder
                .obtain(text, 0, text.length(), tp, contentW)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setLineSpacing(0f, 1.85f)
                .setIncludePad(false)
                .setTextDirection(TextDirectionHeuristics.RTL)
                .build();

            int pages = Math.max(1, (int)Math.ceil((double)Math.max(1, layout.getHeight()) / contentH));
            Paint titlePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            titlePaint.setColor(Color.rgb(31, 95, 91));
            titlePaint.setTextSize(21);
            titlePaint.setTypeface(Typeface.create("sans", Typeface.BOLD));
            titlePaint.setTextAlign(Paint.Align.RIGHT);

            Paint metaPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            metaPaint.setColor(Color.DKGRAY);
            metaPaint.setTextSize(12);
            metaPaint.setTextAlign(Paint.Align.RIGHT);

            for (int pageNo = 0; pageNo < pages; pageNo++) {
                PdfDocument.PageInfo info = new PdfDocument.PageInfo.Builder(PAGE_W, PAGE_H, pageNo + 1).create();
                PdfDocument.Page page = document.startPage(info);
                Canvas c = page.getCanvas();
                c.drawColor(Color.WHITE);

                float right = PAGE_W - MARGIN;
                c.drawText(title, right, MARGIN + 10, titlePaint);
                if (date != null && !date.isEmpty()) c.drawText(date, right, MARGIN + 32, metaPaint);

                Paint line = new Paint();
                line.setColor(Color.rgb(201, 138, 46));
                line.setStrokeWidth(2);
                c.drawLine(MARGIN, MARGIN + 48, PAGE_W - MARGIN, MARGIN + 48, line);

                c.save();
                c.translate(MARGIN, contentTop - (pageNo * contentH));
                layout.draw(c);
                c.restore();
                document.finishPage(page);
            }

            File dir = new File(getContext().getCacheDir(), "exports");
            if (!dir.exists()) dir.mkdirs();
            String safe = sanitize(call.getString("fileName", "intissar-ai.pdf"));
            if (!safe.toLowerCase().endsWith(".pdf")) safe += ".pdf";
            File tmp = new File(dir, safe);
            FileOutputStream fos = new FileOutputStream(tmp);
            document.writeTo(fos);
            fos.close();
            document.close();

            // On Android 10+, also copy to public Downloads so the user can find the PDF.
            Uri publicUri = null;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ContentValues values = new ContentValues();
                values.put(MediaStore.Downloads.DISPLAY_NAME, safe);
                values.put(MediaStore.Downloads.MIME_TYPE, "application/pdf");
                values.put(MediaStore.Downloads.RELATIVE_PATH, "Download/Intissar AI");
                publicUri = getContext().getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
                if (publicUri != null) {
                    try (InputStreamWrapper in = new InputStreamWrapper(new FileInputStream(tmp));
                         OutputStream out = getContext().getContentResolver().openOutputStream(publicUri)) {
                        byte[] buffer = new byte[8192]; int n;
                        while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
                    }
                    try {
                        Intent view = new Intent(Intent.ACTION_VIEW);
                        view.setDataAndType(publicUri, "application/pdf");
                        view.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                        getContext().startActivity(view);
                    } catch (Exception ignored) {
                        // The PDF is still safely saved in Downloads even if no viewer exists.
                    }
                }
            }

            JSObject result = new JSObject();
            result.put("path", tmp.getAbsolutePath());
            result.put("uri", publicUri == null ? "" : publicUri.toString());
            result.put("fileName", safe);
            call.resolve(result);
        } catch (Exception e) {
            Log.e(TAG, "PDF export failed", e);
            try { document.close(); } catch (Exception ignored) {}
            call.reject("تعذر إنشاء PDF: " + e.getMessage(), e);
        }
    }

    private String sanitize(String name) {
        if (name == null || name.isEmpty()) return "intissar-ai.pdf";
        return name.replaceAll("[^a-zA-Z0-9._-]", "_");
    }

    // Small AutoCloseable adapter to keep the copy block tidy.
    private static class InputStreamWrapper extends java.io.InputStream implements AutoCloseable {
        private final FileInputStream in;
        InputStreamWrapper(FileInputStream in){ this.in = in; }
        public int read() throws java.io.IOException { return in.read(); }
        public int read(byte[] b) throws java.io.IOException { return in.read(b); }
        public int read(byte[] b,int o,int l) throws java.io.IOException { return in.read(b,o,l); }
        public void close() throws java.io.IOException { in.close(); }
    }
}
