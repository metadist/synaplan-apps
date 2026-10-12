import Capacitor
import Foundation

/// Marks this binary as able to run a live conversation inside the WebView.
///
/// Audio stays on the relay WebSocket through `getUserMedia`. A native audio
/// graph is a later step, and only if loudspeaker echo cancellation in
/// WKWebView measures too weak. Older binaries do not contain this class, so
/// the SPA keeps the live-conversation button hidden.
///
/// Registered from `SynaplanBridgeViewController` (Capacitor 8 only
/// auto-registers plugins listed in `packageClassList`).
@objc(SynaplanLiveVoicePlugin)
public class SynaplanLiveVoicePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SynaplanLiveVoicePlugin"
    public let jsName = "SynaplanLiveVoice"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
    ]

    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(["available": true])
    }
}
