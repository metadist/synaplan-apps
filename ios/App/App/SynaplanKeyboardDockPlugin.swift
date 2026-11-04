import Capacitor

/// Tells the bridge to pin the WebView to the keyboard while the chat composer
/// is focused. Other fields stay on the overlay path.
@objc(SynaplanKeyboardDockPlugin)
public class SynaplanKeyboardDockPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SynaplanKeyboardDockPlugin"
    public let jsName = "SynaplanKeyboardDock"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setEnabled", returnType: CAPPluginReturnPromise),
    ]

    @objc func setEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        let apply = { [weak self] in
            let controller = self?.bridge?.viewController as? SynaplanBridgeViewController
            controller?.setChatKeyboardDocked(enabled)
            call.resolve()
        }
        // Pointer-down is already on the main thread. Hopping async misses the
        // keyboard animation, so the WebView never joins the guide's move.
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}
