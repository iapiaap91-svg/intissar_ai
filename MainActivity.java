package com.intissarai.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(VoskSttPlugin.class);
        registerPlugin(PdfExportPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
