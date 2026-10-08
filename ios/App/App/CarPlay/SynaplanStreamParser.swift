import Foundation

/// Events of `POST /api/v1/messages/stream` the voice client acts on.
enum SynaplanStreamEvent: Equatable {
    /// Answer text delta (`status: "data"`, `chunk`).
    case text(String)
    /// Terminal success (`status: "complete"`).
    case complete(content: String?, chatTitle: String?)
    /// Terminal failure (`status: "error"`).
    case failure(message: String?)
    /// Guest/rate-limit notice (`status: "message"`).
    case limitReached(message: String?)
}

/// Parses the backend's SSE frames. Every frame is a single
/// `data: {"status": "...", ...}` line; statuses the car does not use
/// (`thinking`, `plan`, `task_*`, `memories_loaded`, …) are skipped.
enum SynaplanStreamParser {
    static func parse(line: String) -> SynaplanStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String else {
            return nil
        }

        switch status {
        case "data":
            guard let chunk = object["chunk"] as? String, !chunk.isEmpty else { return nil }
            return .text(chunk)
        case "complete":
            return .complete(content: object["content"] as? String, chatTitle: object["chatTitle"] as? String)
        case "error":
            return .failure(message: (object["error"] as? String) ?? (object["message"] as? String))
        case "message":
            return .limitReached(message: object["message"] as? String)
        default:
            return nil
        }
    }
}
