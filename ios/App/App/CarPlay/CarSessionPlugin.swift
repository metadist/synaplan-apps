import Capacitor
import Foundation

/// App-local plugin the bootstrap (`app/synaplan-native.js`) uses to tell the
/// native CarPlay layer which server and spoken language the phone app uses.
/// Tokens are never passed through JS; `CarSessionStore` reads them natively.
@objc(SynaplanCarSessionPlugin)
public class SynaplanCarSessionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SynaplanCarSessionPlugin"
    public let jsName = "SynaplanCarSession"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "update", returnType: CAPPluginReturnPromise),
    ]

    @objc func update(_ call: CAPPluginCall) {
        CarSessionStore.shared.update(
            serverUrl: call.getString("serverUrl"),
            language: call.getString("language")
        )
        call.resolve()
    }
}
