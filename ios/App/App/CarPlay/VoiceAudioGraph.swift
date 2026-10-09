import AVFoundation
import Foundation

enum PlaybackEnd {
    case finished
    case interrupted
}

/// One audio engine for the whole conversation. The microphone and the spoken
/// reply share it, with voice processing on, so the echo canceller can take
/// the reply out of the microphone and the driver can talk over it.
///
/// The engine stays running from the first listen until mute or the end.
/// Call `activate`, `play`, and `deactivate` from the main thread. The tap
/// calls back on the audio thread.
final class VoiceAudioGraph {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var handler: ((AVAudioPCMBuffer) -> Void)?
    private var preroll: [AVAudioPCMBuffer] = []
    private var configured = false
    private var playbackContinuation: CheckedContinuation<PlaybackEnd, Never>?
    private var playbackToken = 0
    private(set) var playbackFormat: AVAudioFormat?
    /// False when the device could not enable echo cancellation. Barge-in
    /// stays off then, and the conversation remains turn by turn.
    private(set) var voiceProcessing = false

    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // voiceChat is the two-way mode: it selects a voice route and, together
        // with voice processing below, cancels what the speaker is playing.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
        try session.setActive(true)
        if !configured {
            let format = inputFormat
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechInputError.unavailable
            }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            playbackFormat = format
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
                voiceProcessing = true
            } catch {
                voiceProcessing = false
            }
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.handle(buffer)
            }
            configured = true
        }
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    func deactivate() {
        stopPlayback()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func setHandler(_ handler: ((AVAudioPCMBuffer) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    /// Microphone audio from just before the driver talked over the reply.
    func takePreroll() -> [AVAudioPCMBuffer] {
        lock.lock()
        let buffers = preroll
        preroll = []
        lock.unlock()
        return buffers
    }

    func discardPreroll() {
        lock.lock()
        preroll = []
        lock.unlock()
    }

    /// Plays buffers in `playbackFormat`. When `allowsBargeIn` is set, sustained
    /// speech on the echo-cancelled microphone stops playback.
    func play(_ buffers: [AVAudioPCMBuffer], allowsBargeIn: Bool) async -> PlaybackEnd {
        let playable = buffers.filter { $0.frameLength > 0 }
        guard !playable.isEmpty, engine.isRunning else { return .finished }
        discardPreroll()
        return await withCheckedContinuation { continuation in
            lock.lock()
            playbackToken += 1
            let token = playbackToken
            playbackContinuation = continuation
            lock.unlock()

            if allowsBargeIn {
                let started = ProcessInfo.processInfo.systemUptime
                let detector = BargeInBox()
                setHandler { [weak self] buffer in
                    let elapsed = ProcessInfo.processInfo.systemUptime - started
                    if detector.feed(UtteranceEndpointer.levelDb(of: buffer), at: elapsed) {
                        self?.stopPlayback()
                    }
                }
            }

            let remaining = PlaybackCounter(playable.count)
            for buffer in playable {
                player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    if remaining.decrement() == 0 {
                        self?.finishPlayback(.finished, token: token)
                    }
                }
            }
            player.play()
        }
    }

    func stopPlayback() {
        lock.lock()
        playbackToken += 1
        let token = playbackToken
        lock.unlock()
        player.stop()
        finishPlayback(.interrupted, token: token)
    }

    /// Converts `buffer` into `playbackFormat` when the formats differ.
    func converted(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let playbackFormat else { return nil }
        if buffer.format == playbackFormat { return Self.copy(buffer) }
        guard let converter = AVAudioConverter(from: buffer.format, to: playbackFormat) else { return nil }
        let ratio = playbackFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: max(capacity, 1)) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0 ..< channels {
                destination[channel].update(from: source[channel], count: frames)
            }
            return copy
        }
        if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0 ..< channels {
                destination[channel].update(from: source[channel], count: frames)
            }
            return copy
        }
        return nil
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.copy(buffer) else { return }
        lock.lock()
        preroll.append(copy)
        let maxFrames = Int(copy.format.sampleRate * 0.6)
        var frames = preroll.reduce(0) { $0 + Int($1.frameLength) }
        while frames > maxFrames, !preroll.isEmpty {
            frames -= Int(preroll.removeFirst().frameLength)
        }
        let current = handler
        lock.unlock()
        current?(copy)
    }

    private func finishPlayback(_ end: PlaybackEnd, token: Int) {
        lock.lock()
        guard token == playbackToken, let continuation = playbackContinuation else {
            lock.unlock()
            return
        }
        playbackContinuation = nil
        lock.unlock()
        setHandler(nil)
        continuation.resume(returning: end)
    }
}

private final class PlaybackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int

    init(_ value: Int) {
        self.value = value
    }

    func decrement() -> Int {
        lock.lock()
        value -= 1
        let current = value
        lock.unlock()
        return current
    }
}

/// `BargeInDetector` is a struct, so the audio tap keeps it in a box.
private final class BargeInBox: @unchecked Sendable {
    private let lock = NSLock()
    private var detector = BargeInDetector()

    func feed(_ levelDb: Float, at time: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return detector.feed(levelDb: levelDb, at: time)
    }
}
