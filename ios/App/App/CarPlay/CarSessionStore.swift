import Foundation
import Security
import UIKit

/// Credentials the CarPlay scene needs while the iPhone is locked.
struct CarSession: Equatable {
    let serverUrl: String
    let accessToken: String?
    let refreshToken: String
    let language: String
}

/// Native mirror of the phone app's session for CarPlay.
///
/// The SPA stores its Bearer tokens through `@aparajita/capacitor-secure-storage`
/// with `kSecAttrAccessibleWhenUnlocked`, which CarPlay cannot read while the
/// iPhone is locked (the usual state in a car). While the phone is unlocked this
/// store copies the refresh/access token into its own Keychain items with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (never synchronized), and
/// drops them as soon as the app has signed out. The source item names come
/// from `CarSessionContract`.
final class CarSessionStore {
    static let shared = CarSessionStore()
    static let didChangeNotification = Notification.Name("SynaplanCarSessionDidChange")

    private static let mirrorService = "com.synaplan.carplay.session"
    private static let serverUrlDefaultsKey = "synaplan.carplay.serverUrl"
    private static let languageDefaultsKey = "synaplan.carplay.language"
    private static let supportedLanguages: Set<String> = ["de", "en", "es", "fr", "tr"]

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var protectedDataObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromAppStorage()
        }
    }

    // MARK: - Public state

    var serverUrl: String {
        defaults.string(forKey: Self.serverUrlDefaultsKey) ?? CarSessionContract.defaultServerUrl
    }

    /// Spoken language for recognition, replies, and speech output.
    var language: String {
        if let stored = defaults.string(forKey: Self.languageDefaultsKey), Self.supportedLanguages.contains(stored) {
            return stored
        }
        let preferred = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return Self.supportedLanguages.contains(preferred) ? preferred : "en"
    }

    var session: CarSession? {
        lock.lock()
        defer { lock.unlock() }
        guard let refresh = readMirror(account: "refreshToken") else {
            return nil
        }
        return CarSession(
            serverUrl: serverUrl,
            accessToken: readMirror(account: "accessToken"),
            refreshToken: refresh,
            language: language
        )
    }

    // MARK: - Updates

    /// Called by the bootstrap (via `CarSessionPlugin`) on every SPA load and
    /// whenever the app moves to the background.
    func update(serverUrl rawUrl: String?, language rawLanguage: String?) {
        let url = CarSessionContract.normalizedServerUrl(rawUrl)
        if url != serverUrl {
            defaults.set(url, forKey: Self.serverUrlDefaultsKey)
            clearTokens()
        }
        if let lang = rawLanguage?.lowercased(), Self.supportedLanguages.contains(lang) {
            defaults.set(lang, forKey: Self.languageDefaultsKey)
        }
        syncFromAppStorage()
    }

    /// Copies the phone app's tokens into the mirror. Only possible while
    /// protected data is available (device unlocked); otherwise a no-op.
    func syncFromAppStorage() {
        let run = {
            guard UIApplication.shared.isProtectedDataAvailable else { return }
            self.performSync()
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    func storeAccessToken(_ token: String) {
        lock.lock()
        writeMirror(account: "accessToken", value: token)
        lock.unlock()
    }

    /// Drops the mirrored tokens (sign-out, server switch, revoked refresh token).
    func clearTokens() {
        lock.lock()
        let hadSession = readMirror(account: "refreshToken") != nil
        deleteMirror(account: "accessToken")
        deleteMirror(account: "refreshToken")
        lock.unlock()
        if hadSession {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    // MARK: - Private

    private func performSync() {
        let keys = CarSessionContract.appStorageKeys(for: serverUrl)
        let appRefresh = readAppItem(account: keys.refresh)
        let appAccess = readAppItem(account: keys.access)

        guard let appRefresh else {
            clearTokens()
            return
        }

        lock.lock()
        let previousRefresh = readMirror(account: "refreshToken")
        writeMirror(account: "refreshToken", value: appRefresh)
        if let appAccess {
            writeMirror(account: "accessToken", value: appAccess)
        } else if previousRefresh != appRefresh {
            deleteMirror(account: "accessToken")
        }
        lock.unlock()

        if previousRefresh != appRefresh {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Reads an item written by KeychainSwift inside the SecureStorage plugin
    /// (generic password, account only, no service, not synchronizable).
    private func readAppItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func mirrorQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.mirrorService,
            kSecAttrAccount as String: account,
        ]
    }

    private func readMirror(account: String) -> String? {
        var query = mirrorQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func writeMirror(account: String, value: String) {
        let data = Data(value.utf8)
        let query = mirrorQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private func deleteMirror(account: String) {
        SecItemDelete(mirrorQuery(account: account) as CFDictionary)
    }
}
