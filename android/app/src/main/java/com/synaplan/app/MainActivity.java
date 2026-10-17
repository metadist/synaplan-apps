package com.synaplan.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Before super: BridgeActivity loads the WebView inside onCreate, and
        // only plugins registered by then are injected into the page.
        registerPlugin(SynaplanLiveVoicePlugin.class);
        super.onCreate(savedInstanceState);
    }
}
