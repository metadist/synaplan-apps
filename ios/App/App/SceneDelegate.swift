import Capacitor
import UIKit

/// Phone window scene. `Main.storyboard` (via `UISceneStoryboardFile`) still
/// provides the window and the `SynaplanBridgeViewController` root; this
/// delegate only forwards scene events so Capacitor's URL handling (OAuth deep
/// link, `App.getLaunchUrl()`) keeps working under the UIScene lifecycle.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        (UIApplication.shared.delegate as? AppDelegate)?.window = window
        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        CarSessionStore.shared.syncFromAppStorage()
        CarPermissionPrompt.requestIfPending()
    }

    /// Last moment the phone is guaranteed unlocked: catches a sign-out right
    /// before the user locks the device and drives off.
    func sceneWillResignActive(_ scene: UIScene) {
        CarSessionStore.shared.syncFromAppStorage()
    }
}
