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
/// Call `activate`, `play`, `stopPlayback`, and `deactivate` from the main
/// thread. The tap calls back on the audio thread.
final class VoiceAudioGraph {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let liveStream = PcmPlaybackStream()
    private let liveScratch = MonoScratch()
    private let liveIdle = LiveIdleRelay()
    private var liveSource: AVAudioSourceNode?
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

    var isRunning: Bool { engine.isRunning }

    /// Fires on the main thread once a live reply has finished playing.
    var onLivePlaybackIdle: (() -> Void)? {
        get { liveIdle.fire }
        set { liveIdle.fire = newValue }
    }

    /// True while a reply or a cue is still queued. Ask stays silent then,
    /// because the voice is already the sound.
    var isPlaybackBusy: Bool {
        let playerBusy = engine.attachedNodes.contains(player) && player.isPlaying
        return playerBusy || liveStream.isOutputActive
    }

    /// True while provider audio is still queued or fading. A cue on the
    /// player node does not count: the title follows the reply, not the tone.
    var isLivePlaybackActive: Bool {
        liveStream.isOutputActive
    }

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
            attachLiveSource(format: format)
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
                    guard detector.feed(UtteranceEndpointer.levelDb(of: buffer), at: elapsed) else { return }
                    // AVAudioPlayerNode.stop() waits for the queue this tap runs on.
                    DispatchQueue.main.async { self?.interruptPlayback(token: token) }
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

    /// Plays a cue or a spoken reply on the player node. Live provider audio
    /// does not use this: a new converter per 24 kHz packet clicks. That
    /// stream is `pushLivePcm`, on the source node, so voice processing still
    /// hears it and it does not leak in through a second route.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard engine.isRunning, let playable = converted(buffer), playable.frameLength > 0 else { return }
        player.scheduleBuffer(playable)
        if !player.isPlaying {
            player.play()
        }
    }

    /// One provider packet, at `sourceRate` (24 kHz for a GPT live voice).
    /// The source node resamples it as one continuous signal.
    func pushLivePcm(_ data: Data, sourceRate: Double) {
        liveStream.config(sourceRate)
        liveStream.push(data: data)
    }

    /// The provider stopped talking. A short reply still plays out.
    func endLiveTurn() {
        liveStream.endTurn()
    }

    func stopPlayback() {
        liveStream.flush()
        lock.lock()
        playbackToken += 1
        let token = playbackToken
        lock.unlock()
        player.stop()
        finishPlayback(.interrupted, token: token)
    }

    /// Pulls device-rate samples from the live stream. The node stays
    /// connected for the whole call, so the resampler state never resets.
    private func attachLiveSource(format: AVAudioFormat) {
        let rate = format.sampleRate
        let interleaved = format.isInterleaved
        let channels = Int(format.channelCount)
        let stream = liveStream
        let scratch = liveScratch
        let idle = liveIdle
        let source = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            let frames = Int(frameCount)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard frames > 0, let first = buffers.first, let data = first.mData else {
                isSilence.pointee = true
                return noErr
            }
            let audible: Bool
            if interleaved {
                let mono = scratch.frames(frames)
                audible = stream.render(into: mono, count: frames, deviceRate: rate)
                let destination = data.assumingMemoryBound(to: Float.self)
                for frame in 0 ..< frames {
                    let sample = mono[frame]
                    for channel in 0 ..< max(channels, 1) {
                        destination[frame * max(channels, 1) + channel] = sample
                    }
                }
            } else {
                let destination = data.assumingMemoryBound(to: Float.self)
                audible = stream.render(into: destination, count: frames, deviceRate: rate)
                for buffer in buffers.dropFirst() {
                    guard let pointer = buffer.mData else { continue }
                    pointer.assumingMemoryBound(to: Float.self).update(from: destination, count: frames)
                }
            }
            if stream.takeIdle() {
                idle.signal()
            }
            isSilence.pointee = ObjCBool(!audible)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        liveSource = source
    }

    /// Stops the reply the driver talked over, unless it already ended.
    private func interruptPlayback(token: Int) {
        lock.lock()
        let current = token == playbackToken && playbackContinuation != nil
        lock.unlock()
        guard current else { return }
        stopPlayback()
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


/// One reusable mono buffer for an interleaved render. Grown once, on the
/// first callback that needs it, then only read and written.
private final class MonoScratch: @unchecked Sendable {
    private var storage: UnsafeMutablePointer<Float>?
    private var capacity = 0

    func frames(_ count: Int) -> UnsafeMutablePointer<Float> {
        if count > capacity {
            storage?.deallocate()
            let next = max(count, 4096)
            storage = .allocate(capacity: next)
            capacity = next
        }
        return storage!
    }

    deinit {
        storage?.deallocate()
    }
}

/// Hops the playback-idle mark from the audio thread to the main thread.
private final class LiveIdleRelay: @unchecked Sendable {
    var fire: (() -> Void)?

    func signal() {
        DispatchQueue.main.async { [weak self] in
            self?.fire?()
        }
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
    private var fired = false

    /// True once, for the first buffer that completes a barge-in.
    func feed(_ levelDb: Float, at time: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !fired, detector.feed(levelDb: levelDb, at: time) else { return false }
        fired = true
        return true
    }
}
