import Foundation

/// Actions the Shortcuts app can ask Synaplan to perform after launch.
/// Raw values are the JS contract consumed by `app/synaplan-native.js`.
enum ShortcutAction: String, Sendable {
    case open
    case dictate
    case analyzePhoto = "photo"
}

/// One pending Shortcuts action plus a token so the JS bridge can de-duplicate
/// a cold-start pull (`consume`) against a live plugin event for the same tap.
struct ShortcutActionPayload: Equatable, Sendable {
    let action: ShortcutAction
    let token: String

    var jsObject: [String: String] {
        ["action": action.rawValue, "token": token]
    }
}

/// Process-wide store for the latest Shortcuts action.
///
/// `perform()` on an App Intent can run before the Capacitor bridge (and the
/// SPA) exist, so the value is persisted in `UserDefaults` and survives the
/// cold-start gap. `consume()` is the single clear path — the SPA must call it
/// after handling so a later remount does not replay the same action.
final class ShortcutActionStore: @unchecked Sendable {
    static let shared = ShortcutActionStore()
    static let didChangeNotification = Notification.Name("SynaplanShortcutActionDidChange")

    private static let defaultsKey = "synaplan.pendingShortcutAction"
    private static let tokenKey = "synaplan.pendingShortcutToken"

    private let lock = NSLock()
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func set(_ action: ShortcutAction) {
        let payload = ShortcutActionPayload(action: action, token: UUID().uuidString)
        lock.lock()
        defaults.set(payload.action.rawValue, forKey: Self.defaultsKey)
        defaults.set(payload.token, forKey: Self.tokenKey)
        lock.unlock()

        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: payload.jsObject
        )
    }

    func peek() -> ShortcutActionPayload? {
        lock.lock()
        defer { lock.unlock() }
        return readLocked()
    }

    func consume() -> ShortcutActionPayload? {
        lock.lock()
        let pending = readLocked()
        defaults.removeObject(forKey: Self.defaultsKey)
        defaults.removeObject(forKey: Self.tokenKey)
        lock.unlock()
        return pending
    }

    private func readLocked() -> ShortcutActionPayload? {
        guard
            let raw = defaults.string(forKey: Self.defaultsKey),
            let action = ShortcutAction(rawValue: raw)
        else {
            return nil
        }
        let token = defaults.string(forKey: Self.tokenKey) ?? ""
        return ShortcutActionPayload(action: action, token: token)
    }
}
