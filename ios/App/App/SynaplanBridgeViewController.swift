import Capacitor

/// Capacitor 8 only auto-registers plugins from `packageClassList`. The
/// Shortcuts bridge is app-owned, so it is registered here after the bridge
/// loads — the documented hook for local native code.
class SynaplanBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(SynaplanShortcutsPlugin())
    }
}
