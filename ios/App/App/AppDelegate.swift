import UIKit
import Capacitor

/// Process-level delegate. UI lifecycle, URL opens, and universal links are
/// delivered per scene (`SceneDelegate` for the phone, `CarPlaySceneDelegate`
/// for CarPlay) as declared in `UIApplicationSceneManifest`.
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// The phone window, set by `SceneDelegate`. Plugins such as SplashScreen
    /// still look it up here, and `connectedScenes.first` may be the CarPlay
    /// scene when CarPlay launched the app.
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
}
