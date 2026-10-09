import Capacitor

/// Capacitor 8 only auto-registers plugins from `packageClassList`. The
/// Shortcuts and CarPlay session bridges are app-owned, so they are registered
/// here after the bridge loads — the documented hook for local native code.
class SynaplanBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(SynaplanShortcutsPlugin())
        bridge?.registerPluginInstance(SynaplanCarSessionPlugin())
    }
}
