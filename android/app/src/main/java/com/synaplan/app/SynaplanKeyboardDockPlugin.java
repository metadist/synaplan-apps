package com.synaplan.app;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginHandle;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.lang.reflect.Method;

/**
 * Pins the WebView to the keyboard while the chat composer is focused.
 * Other fields keep {@code adjustNothing} and the SPA scroll assist.
 */
@CapacitorPlugin(name = "SynaplanKeyboardDock")
public class SynaplanKeyboardDockPlugin extends Plugin {

    private ChatKeyboardDock dock;

    @Override
    public void load() {
        if (getBridge() == null || getBridge().getWebView() == null) {
            return;
        }
        dock = new ChatKeyboardDock(getBridge().getWebView(), this::forwardKeyboardEvent);
        getBridge().executeOnMainThread(() -> dock.install());
    }

    private void forwardKeyboardEvent(String event, int cssHeight) {
        if (getBridge() == null) {
            return;
        }
        PluginHandle handle = getBridge().getPlugin("Keyboard");
        if (handle == null || handle.getInstance() == null) {
            return;
        }
        try {
            Method method = handle.getInstance().getClass().getDeclaredMethod(
                "onKeyboardEvent",
                String.class,
                int.class
            );
            method.setAccessible(true);
            method.invoke(handle.getInstance(), event, cssHeight);
        } catch (ReflectiveOperationException ignored) {
            // The keyboard plugin still owns its callback on the normal path.
        }
    }

    @PluginMethod
    public void setEnabled(PluginCall call) {
        boolean enabled = Boolean.TRUE.equals(call.getBoolean("enabled", false));
        getBridge().executeOnMainThread(() -> {
            if (dock != null) {
                dock.setEnabled(enabled);
            }
            call.resolve();
        });
    }
}
