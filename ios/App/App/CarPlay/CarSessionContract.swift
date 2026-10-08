import Foundation

/// Where the phone app keeps its session. Must stay identical to
/// `nativeAuth.ts` in the pinned submodule (`capacitor-storage_` +
/// `syn_native_{at,rt}_<djb2(serverUrl)>`); `tests/carplay-contract.test.mjs`
/// fails when either side drifts.
enum CarSessionContract {
    static let defaultServerUrl = "https://web.synaplan.com"
    static let secureStoragePrefix = "capacitor-storage_"

    /// Same normalization as `getNativeApiBaseUrl()`: trim, drop one trailing slash.
    static func normalizedServerUrl(_ raw: String?) -> String {
        var value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value.isEmpty ? defaultServerUrl : value
    }

    /// Port of `serverScope()` (djb2 over UTF-16 units, int32 wrap-around,
    /// unsigned base-36).
    static func serverScope(for serverUrl: String) -> String {
        var hash: Int32 = 5381
        for unit in serverUrl.utf16 {
            hash = (hash &<< 5) &+ hash &+ Int32(unit)
        }
        return String(UInt32(bitPattern: hash), radix: 36)
    }

    static func appStorageKeys(for serverUrl: String) -> (access: String, refresh: String) {
        let scope = serverScope(for: serverUrl)
        return (
            secureStoragePrefix + "syn_native_at_" + scope,
            secureStoragePrefix + "syn_native_rt_" + scope
        )
    }
}
