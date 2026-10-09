import AVFoundation
import Foundation

enum VoiceState: String, CaseIterable {
    case connecting
    case listening
    case thinking
    case speaking
    case muted
}

/// Why a conversation stopped. Everything except `.userEnded` and `.idle` is
/// shown to the driver as an alert with one recovery sentence.
enum VoiceEndReason: Equatable {
    case userEnded
    case idle
    case signedOut
    case unreachable
    case limitReached
    case microphoneDenied
    case speechUnavailable
    case failed

    var messageKey: String? {
        switch self {
        case .userEnded, .idle: return nil
        case .signedOut: return "error.signedOut"
        case .unreachable: return "error.unreachable"
        case .limitReached: return "error.limitReached"
        case .microphoneDenied: return "error.microphone"
        case .speechUnavailable: return "error.speechUnavailable"
        case .failed: return "error.failed"
        }
    }
}

@MainActor
protocol VoiceConversationEngineDelegate: AnyObject {
    func voiceEngine(_ engine: VoiceConversationEngine, didChange state: VoiceState)
    func voiceEngine(_ engine: VoiceConversationEngine, didEndWith reason: VoiceEndReason, chatId: Int?)
}

/// Hands-free conversation for one CarPlay chat. The driver talks, Synaplan
/// answers out loud, and talking over the answer stops it and becomes the
/// next turn. The loop ends when the driver ends it, stays silent twice, or
/// something fails.
///
/// A new conversation creates its chat lazily on the first utterance, so
/// opening and closing the voice screen never leaves an empty chat behind.
@MainActor
final class VoiceConversationEngine {
    static let silentTurnsBeforeEnding = 2

    weak var delegate: VoiceConversationEngineDelegate?
    private(set) var state: VoiceState = .connecting
    private(set) var chatId: Int?
    private(set) var isMuted = false

    private let client: SynaplanCarClient
    private let store: CarSessionStore
    private let graph: VoiceAudioGraph
    private let output: SpeechOutput
    private let cues = AudioCues()
    private var input: SpeechInput?
    private var loopTask: Task<Void, Never>?
    private var unmuteContinuation: CheckedContinuation<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var ended = false

    init(chatId: Int?, client: SynaplanCarClient = .shared, store: CarSessionStore = .shared) {
        self.chatId = chatId
        self.client = client
        self.store = store
        let graph = VoiceAudioGraph()
        self.graph = graph
        output = SpeechOutput(client: client, graph: graph)
    }

    private enum AnswerResult {
        case done
        case interrupted(String)
        case stop(VoiceEndReason)
    }

    func start() {
        guard loopTask == nil else { return }
        observeAudioSession()
        loopTask = Task { [weak self] in
            await self?.run()
        }
    }

    func toggleMute() {
        guard !ended else { return }
        isMuted.toggle()
        if isMuted {
            let previous = loopTask
            previous?.cancel()
            output.stop()
            set(.muted)
            loopTask = Task { [weak self] in
                await previous?.value
                guard !Task.isCancelled else { return }
                // Muted is not "actively used": give the car its audio back.
                self?.deactivateAudioSession()
                await self?.waitForUnmute()
                await self?.run()
            }
        } else {
            let continuation = unmuteContinuation
            unmuteContinuation = nil
            continuation?.resume()
        }
    }

    func end() {
        finish(.userEnded)
    }

    // MARK: - Loop

    private func run() async {
        guard !ended, !Task.isCancelled else { return }
        if input == nil {
            set(.connecting)
            guard client.isSignedIn else { return finish(.signedOut) }
            switch SpeechPermissions.microphone {
            case .granted:
                break
            case .undetermined:
                CarPermissionPrompt.markPending()
                return finish(.microphoneDenied)
            case .denied:
                return finish(.microphoneDenied)
            }
            guard let created = await makeInput() else { return finish(.speechUnavailable) }
            if Task.isCancelled { return }
            input = created
        }
        guard let input else { return finish(.speechUnavailable) }
        do {
            try activateAudioSession()
        } catch {
            return finish(.failed)
        }

        var silentTurns = 0
        var carried: String?
        while !Task.isCancelled, !ended {
            let transcript: String?
            if let pending = carried {
                transcript = pending
                carried = nil
            } else {
                set(.listening)
                await cues.play(.listening)
                if Task.isCancelled { return }
                do {
                    transcript = try await input.listen(language: store.language, includePreroll: false)
                } catch is CancellationError {
                    return
                } catch SpeechInputError.microphoneDenied {
                    return finish(.microphoneDenied)
                } catch let error as CarClientError {
                    return finish(Self.reason(for: error))
                } catch {
                    return finish(.speechUnavailable)
                }
            }
            if Task.isCancelled { return }

            guard let transcript, !transcript.isEmpty else {
                silentTurns += 1
                if silentTurns >= Self.silentTurnsBeforeEnding {
                    return finish(.idle)
                }
                continue
            }
            silentTurns = 0

            switch await answer(transcript) {
            case .done:
                break
            case let .interrupted(text):
                carried = text.isEmpty ? nil : text
            case let .stop(reason):
                return finish(reason)
            }
        }
    }

    /// Sends one utterance and speaks the reply.
    private func answer(_ transcript: String) async -> AnswerResult {
        set(.thinking)
        await cues.play(.thinking)
        let language = store.language

        do {
            let targetChat: Int
            if let chatId {
                targetChat = chatId
            } else {
                targetChat = try await client.createChat()
                chatId = targetChat
            }

            let (sentences, sentenceSink) = AsyncStream<String>.makeStream()
            let speaker = Task { @MainActor [weak self] in
                guard let self else { return false }
                return await output.speak(sentences, language: language) { [weak self] in
                    self?.set(.speaking)
                }
            }
            let streamTask = Task { @MainActor in
                var chunker = SpokenTextChunker()
                var outcome: VoiceEndReason?
                defer {
                    chunker.finish().forEach { sentenceSink.yield($0) }
                    sentenceSink.finish()
                }
                do {
                    for try await event in client.streamMessage(chatId: targetChat, text: transcript, language: language) {
                        if Task.isCancelled { break }
                        switch event {
                        case let .text(delta):
                            chunker.append(delta).forEach { sentenceSink.yield($0) }
                        case .complete:
                            break
                        case .failure:
                            outcome = .failed
                        case .limitReached:
                            outcome = .limitReached
                        }
                    }
                } catch is CancellationError {
                    return outcome
                } catch let error as CarClientError {
                    return Self.reason(for: error)
                } catch {
                    return VoiceEndReason.unreachable
                }
                return outcome
            }

            let interrupted = await withTaskCancellationHandler {
                await speaker.value
            } onCancel: {
                speaker.cancel()
                streamTask.cancel()
            }
            if interrupted {
                streamTask.cancel()
                _ = await streamTask.value
                set(.listening)
                let text = try await input?.listen(language: language, includePreroll: true)
                return .interrupted(text ?? "")
            }
            let outcome = await streamTask.value
            return outcome.map { .stop($0) } ?? .done
        } catch is CancellationError {
            return .done
        } catch let error as CarClientError {
            return .stop(Self.reason(for: error))
        } catch {
            return .stop(.unreachable)
        }
    }

    private func waitForUnmute() async {
        guard isMuted, !ended, !Task.isCancelled else { return }
        await withCheckedContinuation { continuation in
            unmuteContinuation = continuation
        }
    }

    private func makeInput() async -> SpeechInput? {
        let language = store.language
        if #available(iOS 26.0, *) {
            switch SpeechPermissions.speechRecognition {
            case .granted:
                if await OnDeviceSpeechInput.isReady(language: language) {
                    return OnDeviceSpeechInput(graph: graph)
                }
                OnDeviceSpeechInput.prepare(language: language)
            case .undetermined:
                CarPermissionPrompt.markPending()
            case .denied:
                break
            }
        }
        if await client.serverTranscriptionAvailable() {
            return ServerSpeechInput(client: client, graph: graph)
        }
        return nil
    }

    // MARK: - Ending

    private func finish(_ reason: VoiceEndReason) {
        guard !ended else { return }
        ended = true
        loopTask?.cancel()
        loopTask = nil
        output.stop()
        let continuation = unmuteContinuation
        unmuteContinuation = nil
        continuation?.resume()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()

        let finalChat = chatId
        Task { @MainActor in
            if reason != .userEnded {
                await cues.play(reason == .idle ? .ended : .error)
            }
            if let key = reason.messageKey {
                await output.speakLocally(CarPlayStrings.text(key), language: store.language)
            }
            deactivateAudioSession()
            delegate?.voiceEngine(self, didEndWith: reason, chatId: finalChat)
        }
    }

    private func set(_ newState: VoiceState) {
        guard !ended, state != newState || newState == .listening else { return }
        state = newState
        delegate?.voiceEngine(self, didChange: newState)
    }

    private static func reason(for error: CarClientError) -> VoiceEndReason {
        switch error {
        case .signedOut: return .signedOut
        case .unreachable: return .unreachable
        case .limitReached: return .limitReached
        case .failed: return .failed
        }
    }

    // MARK: - Audio session

    /// Two-way voice: play-and-record in `voiceChat`, with the microphone and
    /// the reply on one engine so the driver can interrupt. Released while
    /// muted and when the conversation ends, so the car gets its audio back.
    private func activateAudioSession() throws {
        try graph.activate()
    }

    private func deactivateAudioSession() {
        graph.deactivate()
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in
                guard let self, !self.isMuted else { return }
                self.toggleMute()
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finish(.failed) }
        })
    }
}
