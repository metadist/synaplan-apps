import CarPlay
import UIKit

/// Entry point of the CarPlay scene (`CPTemplateApplicationSceneSessionRoleApplication`
/// in Info.plist). Runs independently of the phone UI and the WebView; the
/// phone app does not have to be open or unlocked.
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var rootController: CarPlayRootController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        CarSessionStore.shared.syncFromAppStorage()
        let controller = CarPlayRootController(interfaceController: interfaceController)
        rootController = controller
        controller.start()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        rootController?.stop()
        rootController = nil
    }
}
