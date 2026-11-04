package com.synaplan.app;

import android.os.Build;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsAnimation;
import android.webkit.WebView;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import java.lang.reflect.Field;
import java.util.List;

/**
 * Reports the IME's live overlap while the chat composer is focused.
 *
 * <p>Resizing the WebView snaps the page when the inset animation ends. A CSS
 * transition eases on its own clock and the keyboard pulls ahead of the
 * composer. The chat follows {@code onProgress} instead, which is the inset
 * on each frame. The WebView stays full screen.
 */
final class ChatKeyboardDock {

    /** Fires the Capacitor keyboard events when this dock had to replace that plugin's callback. */
    interface KeyboardEvents {
        void onKeyboardEvent(String event, int cssHeight);
    }

    private final View webView;
    @Nullable
    private final KeyboardEvents keyboardEvents;
    private boolean reportFrames;
    private boolean wrapped;
    private int wrapAttempts;
    private int lastPushed = -1;
    private boolean pushInFlight;
    private int pendingPx = -1;

    ChatKeyboardDock(View webView, @Nullable KeyboardEvents keyboardEvents) {
        this.webView = webView;
        this.keyboardEvents = keyboardEvents;
    }

    void install() {
        // The frame callback is installed on first focus, after Capacitor's
        // keyboard plugin has set its own. Installing here would be replaced.
    }

    void setEnabled(boolean enabled) {
        if (!enabled) {
            // Blur can happen as the hide animation starts. Keep reporting
            // until the IME is gone, or the chat stops halfway.
            return;
        }
        reportFrames = true;
        ensureWrapped();
    }

    private void ensureWrapped() {
        if (wrapped || Build.VERSION.SDK_INT < 30) {
            return;
        }
        View root = webView.getRootView();
        WindowInsetsAnimation.Callback existing = existingCallback(root);
        if (existing == null && wrapAttempts < 5) {
            wrapAttempts++;
            root.postDelayed(this::ensureWrapped, 50);
            return;
        }
        wrapRoot(root, existing);
        wrapped = true;
    }

    @RequiresApi(30)
    private void wrapRoot(View root, WindowInsetsAnimation.Callback existing) {
        int mode = existing != null
            ? existing.getDispatchMode()
            : WindowInsetsAnimation.Callback.DISPATCH_MODE_STOP;
        boolean ownsEvents = existing == null;
        root.setWindowInsetsAnimationCallback(new WindowInsetsAnimation.Callback(mode) {
            @Override
            public void onPrepare(@NonNull WindowInsetsAnimation animation) {
                if (existing != null) {
                    existing.onPrepare(animation);
                }
            }

            @NonNull
            @Override
            public WindowInsetsAnimation.Bounds onStart(
                @NonNull WindowInsetsAnimation animation,
                @NonNull WindowInsetsAnimation.Bounds bounds
            ) {
                if (existing != null) {
                    return existing.onStart(animation, bounds);
                }
                if (ownsEvents) {
                    dispatchKeyboardEvent(root, true);
                }
                return bounds;
            }

            @NonNull
            @Override
            public WindowInsets onProgress(
                @NonNull WindowInsets insets,
                @NonNull List<WindowInsetsAnimation> runningAnimations
            ) {
                if (reportFrames) {
                    pushFrame(insets.getInsets(WindowInsets.Type.ime()).bottom);
                }
                if (existing != null) {
                    return existing.onProgress(insets, runningAnimations);
                }
                return insets;
            }

            @Override
            public void onEnd(@NonNull WindowInsetsAnimation animation) {
                if (existing != null) {
                    existing.onEnd(animation);
                } else if (ownsEvents) {
                    dispatchKeyboardEvent(root, false);
                }
                if (!reportFrames) {
                    return;
                }
                WindowInsets insets = root.getRootWindowInsets();
                int ime = insets == null ? 0 : insets.getInsets(WindowInsets.Type.ime()).bottom;
                pushFrame(ime);
                if (ime == 0) {
                    reportFrames = false;
                }
            }
        });
    }

    /**
     * The SDK exposes {@code setWindowInsetsAnimationCallback} and not a getter.
     * The Capacitor keyboard plugin already owns that slot. Reading the field
     * lets this dock run on each frame and still forward show and hide.
     */
    @RequiresApi(30)
    @Nullable
    private WindowInsetsAnimation.Callback existingCallback(View root) {
        try {
            Field field = View.class.getDeclaredField("mWindowInsetsAnimationCallback");
            field.setAccessible(true);
            Object value = field.get(root);
            if (value instanceof WindowInsetsAnimation.Callback) {
                return (WindowInsetsAnimation.Callback) value;
            }
        } catch (ReflectiveOperationException ignored) {
            return null;
        }
        return null;
    }

    @RequiresApi(30)
    private void dispatchKeyboardEvent(View root, boolean starting) {
        if (keyboardEvents == null) {
            return;
        }
        WindowInsets insets = root.getRootWindowInsets();
        boolean visible = insets != null && insets.isVisible(WindowInsets.Type.ime());
        if (!visible) {
            keyboardEvents.onKeyboardEvent(starting ? "keyboardWillHide" : "keyboardDidHide", 0);
            return;
        }
        float density = root.getResources().getDisplayMetrics().density;
        int ime = insets.getInsets(WindowInsets.Type.ime()).bottom;
        int cssPx = density > 0 ? Math.round(ime / density) : ime;
        keyboardEvents.onKeyboardEvent(starting ? "keyboardWillShow" : "keyboardDidShow", cssPx);
    }

    private void pushFrame(int imePx) {
        float density = webView.getResources().getDisplayMetrics().density;
        int cssPx = density > 0 ? Math.round(imePx / density) : imePx;
        if (cssPx < 0) {
            cssPx = 0;
        }
        if (pushInFlight) {
            pendingPx = cssPx;
            return;
        }
        if (cssPx == lastPushed) {
            return;
        }
        if (!(webView instanceof WebView)) {
            return;
        }
        lastPushed = cssPx;
        pushInFlight = true;
        int frame = cssPx;
        ((WebView) webView).evaluateJavascript(
            "window.__synaplanKeyboardFrame&&window.__synaplanKeyboardFrame(" + frame + ")",
            value -> {
                pushInFlight = false;
                if (pendingPx < 0 || pendingPx == lastPushed) {
                    pendingPx = -1;
                    return;
                }
                int next = pendingPx;
                pendingPx = -1;
                lastPushed = -1;
                pushFrame(Math.round(next * density));
            }
        );
    }
}
