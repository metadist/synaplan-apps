import Foundation

/// Gapless PCM16 playback, the same stream the website uses for a live voice.
///
/// GPT live audio is 24 kHz. The car plays at the microphone rate, usually
/// 48 kHz. Chunks are one signal: the read position carries across the
/// boundary, and the last sample of a chunk interpolates against the first
/// sample of the next one. A fresh resampler per packet clicks at every
/// boundary, which is the crackle this replaces.
///
/// `render` is called from the audio thread. `push`, `endTurn`, and `flush`
/// run on the main thread.
final class PcmPlaybackStream: @unchecked Sendable {
    static let prebufferSeconds: Double = 0.08
    static let startStallSeconds: Double = 0.15

    private let lock = NSLock()
    private var assembler = PcmFrameAssembler()
    private var samples: [Float] = []
    private var fraction: Double = 0
    private var sourceRate: Double = 24_000
    private var playing = false
    private var idleSent = false
    private var silence = 0
    private var started = false
    private var fadeIn: Double = 0
    private var fadeOut: Double = 1
    private var fadingOut = false
    private var lastSample: Float = 0
    private var turnEnded = false
    private var stall = 0
    /// Set once when a turn has drained. The audio thread only raises it;
    /// `takeIdle` clears it on the same thread that renders.
    private var idlePending = false

    /// True from the first queued sample until the turn has drained and gone idle.
    var isOutputActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return playing || fadingOut || started
    }

    func config(_ sourceRate: Double) {
        lock.lock()
        self.sourceRate = sourceRate > 0 ? sourceRate : 24_000
        lock.unlock()
    }

    /// Little-endian PCM16. A trailing odd byte waits for the next packet,
    /// so a split frame is not played as swapped bytes.
    func push(data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let frames = assembler.push(data), !frames.isEmpty else { return }
        appendUnlocked(frames)
    }

    func push(pcm: [Int16]) {
        guard !pcm.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        appendUnlocked(pcm)
    }

    /// A short reply has no further audio. Play what is buffered instead of
    /// waiting out the stall. GPT live sends no separate "audio finished".
    func endTurn() {
        lock.lock()
        turnEnded = true
        lock.unlock()
    }

    func flush() {
        lock.lock()
        samples = []
        fraction = 0
        silence = 0
        playing = false
        idleSent = false
        started = false
        fadeIn = 0
        fadeOut = 1
        fadingOut = false
        lastSample = 0
        turnEnded = false
        stall = 0
        idlePending = false
        assembler.reset()
        lock.unlock()
    }

    /// True once, when the reply has been silent long enough to count as over.
    /// A later packet clears it, so a stale idle cannot land on the next turn.
    func takeIdle() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard idlePending else { return false }
        idlePending = false
        return true
    }

    /// Writes `count` device-rate frames. Returns true when any sample was audible.
    func render(into output: UnsafeMutablePointer<Float>, count: Int, deviceRate: Double) -> Bool {
        guard count > 0, deviceRate > 0 else { return false }
        lock.lock()
        defer { lock.unlock() }
        let step = sourceRate / deviceRate
        let prebuffer = sourceRate * Self.prebufferSeconds
        let fadeSamples = Double(max(1, Int((deviceRate * 0.005).rounded())))
        var wrote = false

        for index in 0 ..< count {
            if fadingOut {
                fadeOut = max(0, fadeOut - 1 / fadeSamples)
                output[index] = lastSample * Float(fadeOut)
                if fadeOut == 0 {
                    fadingOut = false
                    started = false
                    lastSample = 0
                    fadeIn = 0
                } else {
                    wrote = true
                }
                continue
            }

            if !started {
                let buffered = bufferedSamples()
                stall = buffered > 0 ? stall + 1 : 0
                let stalled = Double(stall) >= deviceRate * Self.startStallSeconds
                let ready = buffered >= prebuffer || (buffered > 0 && (turnEnded || stalled))
                if !ready {
                    output[index] = 0
                    continue
                }
                started = true
                fadeIn = 0
                stall = 0
            }

            guard let sample = read(step) else {
                fadingOut = true
                fadeOut = max(0, 1 - 1 / fadeSamples)
                output[index] = lastSample * Float(fadeOut)
                if fadeOut == 0 {
                    fadingOut = false
                    started = false
                    lastSample = 0
                } else {
                    wrote = true
                }
                continue
            }

            fadeIn = min(1, fadeIn + 1 / fadeSamples)
            output[index] = sample * Float(fadeIn)
            lastSample = sample
            wrote = true
        }

        if wrote {
            silence = 0
            return true
        }

        if playing && !idleSent && bufferedSamples() == 0 && !started {
            silence += count
            if Double(silence) > deviceRate * 0.3 {
                idleSent = true
                playing = false
                idlePending = true
            }
        }
        return false
    }

    private func appendUnlocked(_ pcm: [Int16]) {
        samples.reserveCapacity(samples.count + pcm.count)
        for sample in pcm {
            samples.append(Float(sample) / 32768)
        }
        silence = 0
        playing = true
        idleSent = false
        idlePending = false
        turnEnded = false
        stall = 0
    }

    private func bufferedSamples() -> Double {
        let left = Double(samples.count) - fraction
        return left > 0 ? left : 0
    }

    private func read(_ step: Double) -> Float? {
        if fraction >= Double(samples.count) {
            samples = []
            fraction = 0
            return nil
        }
        let index = Int(fraction.rounded(.down))
        let frac = fraction - Double(index)
        let current = samples[index]
        let next = index + 1 < samples.count ? samples[index + 1] : current
        let sample = current + (next - current) * Float(frac)
        fraction += step
        let drop = Int(fraction.rounded(.down)) - 1
        if drop > 2048 && drop < samples.count {
            samples.removeFirst(drop)
            fraction -= Double(drop)
        }
        return sample
    }
}

/// Keeps a trailing odd PCM byte so the next packet completes the frame.
struct PcmFrameAssembler {
    private var pending: UInt8?

    mutating func reset() {
        pending = nil
    }

    mutating func push(_ data: Data) -> [Int16]? {
        let incoming = [UInt8](data)
        let total = incoming.count + (pending == nil ? 0 : 1)
        let even = total - (total % 2)
        if even == 0 {
            if incoming.count == 1 {
                pending = incoming.first
            }
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: even)
        var offset = 0
        if let pending {
            bytes[0] = pending
            offset = 1
        }
        let take = even - offset
        for index in 0 ..< take {
            bytes[offset + index] = incoming[index]
        }
        pending = total % 2 == 1 ? incoming.last : nil
        var frames = [Int16]()
        frames.reserveCapacity(even / 2)
        var index = 0
        while index < even {
            let low = UInt16(bytes[index])
            let high = UInt16(bytes[index + 1]) << 8
            frames.append(Int16(bitPattern: low | high))
            index += 2
        }
        return frames
    }
}
