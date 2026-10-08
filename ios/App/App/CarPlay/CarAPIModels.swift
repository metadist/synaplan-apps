import Foundation

/// Chat row shown in the CarPlay list.
struct CarChatSummary: Equatable {
    let id: Int
    let title: String
    let updatedAt: Date?
    var pinned = false
}

enum CarClientError: Error, Equatable {
    /// No session, or the server rejected the refresh token.
    case signedOut
    /// Network failure, timeout, or a 5xx/429 the user can retry.
    case unreachable
    /// Usage limit reached for this account.
    case limitReached
    /// The request was understood but failed server-side.
    case failed
}

/// Response decoding for the endpoints the car uses. The shapes are pinned by
/// `tests/carplay-contract.test.mjs` against the generated OpenAPI schemas.
enum CarAPIDecoding {
    /// Titles the backend reports for a chat that has no generated title yet.
    static let placeholderTitles: Set<String> = ["New Chat", "Neuer Chat"]

    /// `GET /api/v1/chats?limit=…` → the user's own web chats, pinned first,
    /// otherwise in the server's newest-activity order. An empty title means
    /// "untitled".
    static func chatList(_ data: Data) throws -> [CarChatSummary] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chats = object["chats"] as? [[String: Any]] else {
            throw CarClientError.failed
        }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let summaries: [CarChatSummary] = chats.compactMap { chat in
            guard let id = chat["id"] as? Int else { return nil }
            // Widget visitor conversations belong to the widget, not to the user's own chats.
            if let widget = chat["widgetSession"], !(widget is NSNull) { return nil }
            // Channel conversations (WhatsApp, email, Telegram, …) belong to their
            // channel, and their titles can carry phone numbers or addresses.
            if let source = chat["source"] as? String, source != "web" { return nil }
            let rawDate = chat["updatedAt"] as? String ?? ""
            let title = (chat["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return CarChatSummary(
                id: id,
                title: placeholderTitles.contains(title) ? "" : title,
                updatedAt: iso.date(from: rawDate) ?? isoFractional.date(from: rawDate),
                pinned: chat["pinned"] as? Bool ?? false
            )
        }
        return summaries.filter(\.pinned) + summaries.filter { !$0.pinned }
    }

    /// `POST /api/v1/chats` → id of the new chat.
    static func createdChatId(_ data: Data) throws -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chat = object["chat"] as? [String: Any],
              let id = chat["id"] as? Int else {
            throw CarClientError.failed
        }
        return id
    }

    /// `POST /api/v1/auth/refresh` → new access token, or nil when the server
    /// did not issue one (session revoked).
    static func refreshedAccessToken(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let access = tokens["accessToken"] as? String, !access.isEmpty else {
            return nil
        }
        return access
    }

    /// `POST /api/v1/messages/upload-file` with `purpose=dictation` → transcript.
    static func dictationText(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CarClientError.failed
        }
        return ((object["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `GET /api/v1/config/runtime` → `speech.speechToTextAvailable`.
    static func serverTranscriptionAvailable(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let speech = object["speech"] as? [String: Any] else {
            return false
        }
        return speech["speechToTextAvailable"] as? Bool ?? false
    }

    /// `Synaplan Mobile V<major>.<minor>` — the backend only returns Bearer
    /// tokens to clients matching `ClientContextResolver::UA_PATTERN`.
    static func userAgent(shortVersion: String?) -> String {
        let parts = (shortVersion ?? "").split(separator: ".").prefix(2).compactMap { Int($0) }
        let major = parts.first ?? 1
        let minor = parts.count > 1 ? parts[1] : 0
        return "Synaplan Mobile V\(major).\(minor) CarPlay"
    }
}
