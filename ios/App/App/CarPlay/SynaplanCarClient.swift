import Foundation

/// Minimal native client for the endpoints the car needs. Response decoding
/// lives in `CarAPIDecoding`.
final class SynaplanCarClient {
    static let shared = SynaplanCarClient()

    static let chatListLimit = 12
    /// Fetched rows before widget and channel chats are filtered out.
    private static let chatFetchLimit = 30
    private static let requestTimeout: TimeInterval = 20
    private static let streamTimeout: TimeInterval = 120

    private let store: CarSessionStore
    private let urlSession: URLSession
    private let tokens: TokenBroker

    init(store: CarSessionStore = .shared) {
        self.store = store
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        urlSession = URLSession(configuration: configuration)
        tokens = TokenBroker(store: store, urlSession: urlSession)
    }

    static let userAgent = CarAPIDecoding.userAgent(
        shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    )

    var isSignedIn: Bool {
        store.session != nil
    }

    // MARK: - Chats

    func listChats() async throws -> [CarChatSummary] {
        var components = URLComponents(string: store.serverUrl + "/api/v1/chats")
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(Self.chatFetchLimit)),
            URLQueryItem(name: "offset", value: "0"),
        ]
        guard let url = components?.url else { throw CarClientError.failed }
        return try CarAPIDecoding.chatList(try await send(URLRequest(url: url)))
    }

    func createChat() async throws -> Int {
        guard let url = URL(string: store.serverUrl + "/api/v1/chats") else { throw CarClientError.failed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return try CarAPIDecoding.createdChatId(try await send(request))
    }

    // MARK: - Messages

    /// Streams one turn. Text deltas arrive as they are generated; the stream
    /// always ends with `.complete`, `.failure`, `.limitReached`, or an error.
    func streamMessage(chatId: Int, text: String, language: String) -> AsyncThrowingStream<SynaplanStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: self.store.serverUrl + "/api/v1/messages/stream") else {
                        throw CarClientError.failed
                    }
                    var request = URLRequest(url: url, timeoutInterval: Self.streamTimeout)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "message": text,
                        "chatId": String(chatId),
                        "language": language,
                    ])

                    let (bytes, response) = try await self.authorizedBytes(for: request)
                    try Self.check(response)
                    var terminal = false
                    for try await line in bytes.lines {
                        guard let event = SynaplanStreamParser.parse(line: line) else { continue }
                        continuation.yield(event)
                        if case .text = event { continue }
                        terminal = true
                        break
                    }
                    if !terminal {
                        throw CarClientError.unreachable
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Speech

    /// Synthesizes one sentence with the user's configured TTS provider.
    func speech(text: String, language: String) async throws -> (data: Data, contentType: String) {
        var components = URLComponents(string: store.serverUrl + "/api/v1/tts/stream")
        components?.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "mp3"),
        ]
        guard let url = components?.url else { throw CarClientError.failed }
        let (data, response) = try await authorizedData(for: URLRequest(url: url))
        try Self.check(response)
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        return (data, contentType.lowercased())
    }

    /// Server-side transcription fallback (`purpose=dictation` stores nothing).
    func transcribe(audioFile: URL) async throws -> String {
        guard let url = URL(string: store.serverUrl + "/api/v1/messages/upload-file") else {
            throw CarClientError.failed
        }
        let boundary = "synaplan-car-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("purpose", "dictation")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"car-dictation.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(try Data(contentsOf: audioFile))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url, timeoutInterval: Self.streamTimeout)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try CarAPIDecoding.dictationText(try await send(request))
    }

    /// `speech.speechToTextAvailable` from the public runtime config.
    func serverTranscriptionAvailable() async -> Bool {
        guard let url = URL(string: store.serverUrl + "/api/v1/config/runtime") else { return false }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return false
        }
        return CarAPIDecoding.serverTranscriptionAvailable(data)
    }

    // MARK: - Transport

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await authorizedData(for: request)
            try Self.check(response)
            return data
        } catch {
            throw Self.mapped(error)
        }
    }

    private func authorizedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let first = try await urlSession.data(for: prepared(request, token: try await tokens.accessToken()))
        guard (first.1 as? HTTPURLResponse)?.statusCode == 401 else { return first }
        let fresh = try await tokens.refresh()
        return try await urlSession.data(for: prepared(request, token: fresh))
    }

    private func authorizedBytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let first = try await urlSession.bytes(for: prepared(request, token: try await tokens.accessToken()))
        guard (first.1 as? HTTPURLResponse)?.statusCode == 401 else { return first }
        first.0.task.cancel()
        let fresh = try await tokens.refresh()
        return try await urlSession.bytes(for: prepared(request, token: fresh))
    }

    private func prepared(_ request: URLRequest, token: String) -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw CarClientError.unreachable }
        switch status {
        case 200 ..< 300: return
        case 401: throw CarClientError.signedOut
        case 402: throw CarClientError.limitReached
        case 408, 429, 500...: throw CarClientError.unreachable
        default: throw CarClientError.failed
        }
    }

    private static func mapped(_ error: Error) -> Error {
        if error is CarClientError || error is CancellationError { return error }
        if let urlError = error as? URLError, urlError.code == .cancelled { return CancellationError() }
        return CarClientError.unreachable
    }
}

/// Serializes access-token refreshes so parallel requests (chat list, TTS
/// prefetch) never fire more than one `/auth/refresh`.
private actor TokenBroker {
    private let store: CarSessionStore
    private let urlSession: URLSession
    private var inFlight: Task<String, Error>?

    init(store: CarSessionStore, urlSession: URLSession) {
        self.store = store
        self.urlSession = urlSession
    }

    func accessToken() async throws -> String {
        guard let session = store.session else { throw CarClientError.signedOut }
        if let token = session.accessToken { return token }
        return try await refresh()
    }

    func refresh() async throws -> String {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await self.performRefresh() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let session = store.session,
              let url = URL(string: session.serverUrl + "/api/v1/auth/refresh") else {
            throw CarClientError.signedOut
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SynaplanCarClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": session.refreshToken])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw CarClientError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 408 || status == 429 || status >= 500 || status == 0 {
            throw CarClientError.unreachable
        }
        guard status == 200, let access = CarAPIDecoding.refreshedAccessToken(data) else {
            store.clearTokens()
            throw CarClientError.signedOut
        }
        store.storeAccessToken(access)
        return access
    }
}
