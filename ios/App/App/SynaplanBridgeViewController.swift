import Capacitor

/// Capacitor 8 only auto-registers plugins from `packageClassList`. The
/// Shortcuts, CarPlay session, and live-voice bridges are app-owned, so they
/// are registered here after the bridge loads — the documented hook for local
/// native code. This runs before the WebView loads its first page.
class SynaplanBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(SynaplanShortcutsPlugin())
        bridge?.registerPluginInstance(SynaplanCarSessionPlugin())
        bridge?.registerPluginInstance(SynaplanLiveVoicePlugin())
    }
}
