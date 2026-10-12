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
    private let onState: (VoiceState) -> Void
    private var socket: URLSessionWebSocketTask?
    private var sending = false
    private var muted = false
    private var stopping = false
    private var inRate = 24_000
    private var outRate = 24_000
    private var heardGoodbye = false
    private var sawReady = false

    init(client: SynaplanCarClient, graph: VoiceAudioGraph, onState: @escaping (VoiceState) -> Void) {
        self.client = client
        self.graph = graph
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
        onState(muted ? .muted : .listening)
    }

    func run(_ start: LiveVoiceStart) async -> (stop: LiveVoiceStop, heardGoodbye: Bool) {
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
                    if let end = handle(text) { return end }
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

    private func handle(_ text: String) -> SocketEnd? {
        switch LiveVoiceCarPlan.frame(from: text) {
        case .ready:
            sawReady = true
            sending = true
            graph.setHandler { [weak self] buffer in
                guard let copy = VoiceAudioGraph.copy(buffer) else { return }
                Task { @MainActor in
                    self?.sendMic(copy)
                }
            }
            onState(.listening)
            return nil
        case let .state(name):
            if name == "thinking" { onState(.thinking) }
            else if name == "speaking" { onState(.speaking) }
            else if !muted { onState(.listening) }
            return nil
        case .interrupted:
            graph.stopPlayback()
            if !muted { onState(.listening) }
            return nil
        case .wrapUp:
            heardGoodbye = true
            onState(.speaking)
            return nil
        case let .ended(reason):
            stopAudio()
            return .remote(reason)
        case .ignored:
            return nil
        }
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
        let samples = PCM16.decode(data)
        guard !samples.isEmpty else { return }
        onState(.speaking)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(outRate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                buffer.floatChannelData?[0].update(from: base, count: samples.count)
            }
        }
        graph.enqueue(buffer)
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
