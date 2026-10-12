package com.synaplan.app;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * Marks this binary as able to run a live conversation inside the WebView.
 *
 * Audio stays on the relay WebSocket. Capacitor's WebChromeClient already
 * grants {@code RESOURCE_AUDIO_CAPTURE} when {@code RECORD_AUDIO} is declared.
 * A native audio graph is a later step, and only if loudspeaker echo
 * cancellation in the WebView measures too weak. Older binaries do not
 * contain this class, so the SPA keeps the live-conversation button hidden.
 */
@CapacitorPlugin(name = "SynaplanLiveVoice")
public class SynaplanLiveVoicePlugin extends Plugin {

    @PluginMethod
    public void isAvailable(PluginCall call) {
        JSObject result = new JSObject();
        result.put("available", true);
        call.resolve(result);
    }
}
