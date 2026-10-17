import AVFoundation
import Foundation

/// One full-duplex CarPlay conversation over the relay socket.
///
/// The microphone is PCM16 at the rate the server asked for. Provider audio
/// is played on the same graph, with voice processing left on. The provider
/// handles barge-in, so this path does not run the local detector.
@MainActor
final class LiveVoiceSession {
    private let client: SynaplanCarClient
    private let graph: VoiceAudioGraph
    private let cues: AudioCues
    private let onState: (VoiceState) -> Void
    private var socket: URLSessionWebSocketTask?
    private var sending = false
    private var muted = false
    private var stopping = false
    private var inRate = 24_000
    private var outRate = 24_000
    private var heardGoodbye = false
    private var sawReady = false
    private var cuePhase: LiveVoicePhase = .idle
    /// The phase the car title is showing. Speaking lasts until the reply
    /// audio has drained; the relay itself only sends thinking.
    private var shown: LiveVoicePhase = .idle
    private var lastAsk: Date?
    /// True after the opening tone. A reconnect inside the same call does not play it again.
    private(set) var didPlayOpen = false

    init(
        client: SynaplanCarClient,
        graph: VoiceAudioGraph,
        cues: AudioCues,
        onState: @escaping (VoiceState) -> Void
    ) {
        self.client = client
        self.graph = graph
        self.cues = cues
        self.onState = onState
    }

    func stop() {
        stopping = true
        sendControl("end")
        stopAudio()
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        sendControl(muted ? "mute" : "unmute")
        if muted {
            onState(.muted)
        } else {
            shown = .listening
            onState(.listening)
        }
    }

    func run(_ start: LiveVoiceStart) async -> (stop: LiveVoiceStop, heardGoodbye: Bool) {
        graph.onLivePlaybackIdle = { [weak self] in
            self?.notePlaybackIdle()
        }
        defer { graph.onLivePlaybackIdle = nil }
        var current = start
        var droppedAt: Date?
        while !Task.isCancelled && !stopping {
            switch await connect(current) {
            case let .remote(reason):
                return (LiveVoiceCarPlan.stop(for: reason), heardGoodbye)
            case .failed:
                stopAudio()
                return sawReady ? (.network, heardGoodbye) : (.turnBased(.down), heardGoodbye)
            case .dropped:
                stopAudio()
                if stopping { return (.quiet, heardGoodbye) }
                if !sawReady { return (.turnBased(.down), heardGoodbye) }
                if droppedAt == nil { droppedAt = Date() }
                guard let since = droppedAt, LiveVoiceCarPlan.reconnectOpen(since: since, now: Date()) else {
                    return (.network, heardGoodbye)
                }
                guard let resumed = await client.liveResumeTicket(sessionId: current.sessionId) else {
                    return (.network, heardGoodbye)
                }
                current = resumed
            }
        }
        sendControl("end")
        stopAudio()
        return (.quiet, heardGoodbye)
    }

    private enum SocketEnd {
        case remote(String)
        case dropped
        case failed
    }

    private func connect(_ start: LiveVoiceStart) async -> SocketEnd {
        guard let url = URL(string: start.wsUrl) else { return .failed }
        inRate = start.inRate
        outRate = start.outRate
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        await playTransition(to: .connecting)
        shown = .connecting
        onState(.connecting)
        return await withTaskCancellationHandler {
            await receive(task)
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    private func receive(_ task: URLSessionWebSocketTask) async -> SocketEnd {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case let .data(data):
                    play(data)
                case let .string(text):
                    if let end = await handle(text) { return end }
                @unknown default:
                    break
                }
            } catch is CancellationError {
                return .dropped
            } catch {
                return stopping ? .remote("user_end") : .dropped
            }
        }
        return .dropped
    }

    private func handle(_ text: String) async -> SocketEnd? {
        switch LiveVoiceCarPlan.frame(from: text) {
        case .ready:
            show(.ready)
            // The tone finishes before the microphone opens, so the relay
            // does not hear the ready chime as the first utterance.
            if !muted, !stopping {
                await cues.play(.ready, through: graph)
            }
            cuePhase = .listening
            guard !stopping, !Task.isCancelled else { return nil }
            sawReady = true
            sending = true
            graph.setHandler { [weak self] buffer in
                guard let copy = VoiceAudioGraph.copy(buffer) else { return }
                Task { @MainActor in
                    self?.sendMic(copy)
                }
            }
            return nil
        case let .state(name):
            show(.state(name))
            if name == "thinking" {
                await playTransition(to: .thinking)
            } else if name == "speaking" {
                cuePhase = .speaking
            } else if !muted {
                // The reply is over. Play out a short tail instead of holding
                // it for the stall, the same as the website's end-of-turn.
                graph.endLiveTurn()
                if cuePhase != .connecting { cuePhase = .listening }
            }
            return nil
        case .interrupted:
            graph.stopPlayback()
            if !muted { show(.interrupted) }
            if cuePhase != .connecting { cuePhase = .listening }
            return nil
        case .wrapUp:
            heardGoodbye = true
            show(.wrapUp)
            cuePhase = .ending
            return nil
        case let .ended(reason):
            stopAudio()
            return .remote(reason)
        case .ignored:
            return nil
        }
    }

    /// Opening tone only from idle or ended. A reconnect is already in the
    /// call, so connecting again stays silent. Ask is gated so it never sits
    /// on top of a reply or an unprotected microphone.
    private func playTransition(to next: LiveVoicePhase, reason: String = "") async {
        let previous = cuePhase
        cuePhase = next
        guard !muted, !stopping else { return }
        guard let cue = LiveVoiceCuePlan.cue(previous: previous, next: next, reason: reason) else { return }
        if cue == .ask {
            guard LiveVoiceCuePlan.shouldPlayAsk(
                voiceProcessing: graph.voiceProcessing,
                playbackBusy: graph.isPlaybackBusy,
                now: Date(),
                lastAsk: lastAsk
            ) else { return }
            lastAsk = Date()
        }
        if cue == .open { didPlayOpen = true }
        await cues.play(cue, through: graph)
    }

    private func sendMic(_ buffer: AVAudioPCMBuffer) {
        guard sending, !muted, let channel = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: frames))
        let pcm = PCM16.encode(PCM16.resample(samples, from: buffer.format.sampleRate, to: Double(inRate)))
        guard !pcm.isEmpty, let socket else { return }
        socket.send(.data(pcm)) { _ in }
    }

    private func play(_ data: Data) {
        guard !data.isEmpty else { return }
        show(.audio)
        if cuePhase != .ending { cuePhase = .speaking }
        graph.pushLivePcm(data, sourceRate: Double(outRate))
    }

    /// The reply buffer has drained. Listening again, unless a newer phase
    /// (thinking, a goodbye) already took over, or the next turn has audio.
    private func notePlaybackIdle() {
        guard !stopping, !muted, !graph.isLivePlaybackActive else { return }
        let wasSpeaking = shown == .speaking
        show(.playbackIdle)
        if wasSpeaking, shown == .listening, cuePhase == .speaking {
            cuePhase = .listening
        }
    }

    private func show(_ signal: LiveVoiceSignal) {
        let next = LiveVoiceCarPlan.phase(after: shown, signal: signal)
        shown = next
        guard let state = Self.voiceState(for: next) else { return }
        onState(state)
    }

    private static func voiceState(for phase: LiveVoicePhase) -> VoiceState? {
        switch phase {
        case .connecting: return .connecting
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking, .ending: return .speaking
        case .idle, .ended: return nil
        }
    }

    private func sendControl(_ type: String) {
        guard let socket else { return }
        let text = "{\"type\":\"\(type)\"}"
        socket.send(.string(text)) { _ in }
    }

    private func stopAudio() {
        sending = false
        graph.setHandler(nil)
        graph.stopPlayback()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }
}
