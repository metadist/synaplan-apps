import Capacitor
import Foundation

/// App-local Capacitor plugin that surfaces pending Shortcuts actions to JS.
///
/// Registered from `SynaplanBridgeViewController` via `registerPluginInstance`
/// (Capacitor 8 only auto-registers plugins listed in `packageClassList`).
@objc(SynaplanShortcutsPlugin)
public class SynaplanShortcutsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SynaplanShortcutsPlugin"
    public let jsName = "SynaplanShortcuts"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "consumePendingAction", returnType: CAPPluginReturnPromise),
    ]

    private var observer: NSObjectProtocol?

    override public func load() {
        observer = NotificationCenter.default.addObserver(
            forName: ShortcutActionStore.didChangeNotification,
            object: ShortcutActionStore.shared,
            queue: .main
        ) { [weak self] notification in
            var payload: [String: Any] = [:]
            if let action = notification.userInfo?["action"] as? String {
                payload["action"] = action
            }
            if let token = notification.userInfo?["token"] as? String {
                payload["token"] = token
            }
            self?.notifyListeners("shortcutAction", data: payload)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc func consumePendingAction(_ call: CAPPluginCall) {
        if let pending = ShortcutActionStore.shared.consume() {
            call.resolve(pending.jsObject)
            return
        }
        call.resolve([:])
    }
}
