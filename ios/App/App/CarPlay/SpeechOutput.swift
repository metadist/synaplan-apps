import AVFoundation
import Foundation

/// Speaks an answer sentence by sentence. Each sentence is synthesized with
/// the user's Synaplan TTS provider as soon as it arrives, so the next one is
/// usually ready when the previous one ends. When the server cannot deliver a
/// format AVFoundation plays (e.g. Piper's WebM) or is unreachable, the system
/// voice takes over for the rest of the conversation.
@MainActor
final class SpeechOutput: NSObject {
    private enum Utterance {
        case audio(Data)
        case system(String)
    }

    private static let playableContentTypes = ["audio/mpeg", "audio/mp3", "audio/aac", "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/wav", "audio/x-wav"]

    /// AVAudioFile picks the decoder from the extension, not from the bytes.
    private static func audioExtension(for data: Data) -> String {
        if data.starts(with: Data("RIFF".utf8)) { return "wav" }
        if data.starts(with: Data("ID3".utf8)) { return "mp3" }
        if data.count > 1, data[0] == 0xFF, (data[1] & 0xE0) == 0xE0 { return "mp3" }
        return "m4a"
    }

    private let client: SynaplanCarClient
    private let graph: VoiceAudioGraph
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var useSystemVoice = false

    init(client: SynaplanCarClient, graph: VoiceAudioGraph) {
        self.client = client
        self.graph = graph
        super.init()
        synthesizer.delegate = self
    }

    /// Plays every sentence from `sentences` in order. Returns true when the
    /// driver talked over the reply and playback stopped.
    func speak(_ sentences: AsyncStream<String>, language: String, onFirstAudio: @escaping () -> Void) async -> Bool {
        let (fetches, fetchContinuation) = AsyncStream<Task<Utterance, Never>>.makeStream()
        let producer = Task { @MainActor in
            for await sentence in sentences {
                fetchContinuation.yield(Task { @MainActor in await self.prepare(sentence, language: language) })
            }
            fetchContinuation.finish()
        }

        var interrupted = false
        await withTaskCancellationHandler {
            var started = false
            for await fetch in fetches {
                if Task.isCancelled || interrupted { break }
                let utterance = await fetch.value
                if Task.isCancelled || interrupted { break }
                if !started {
                    started = true
                    onFirstAudio()
                }
                if await play(utterance, language: language) == .interrupted {
                    interrupted = true
                }
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
        producer.cancel()
        return interrupted
    }

    /// Speaks a short app-generated sentence with the system voice.
    func speakLocally(_ text: String, language: String) async {
        await play(.system(text), language: language)
    }

    func stop() {
        graph.stopPlayback()
        player?.stop()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resumePlayback()
    }

    private func prepare(_ sentence: String, language: String) async -> Utterance {
        if useSystemVoice { return .system(sentence) }
        do {
            let result = try await client.speech(text: sentence, language: language)
            let type = result.contentType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if Self.playableContentTypes.contains(type), !result.data.isEmpty {
                return .audio(result.data)
            }
        } catch is CancellationError {
            return .system("")
        } catch {}
        useSystemVoice = true
        return .system(sentence)
    }

    private func play(_ utterance: Utterance, language: String) async -> PlaybackEnd {
        switch utterance {
        case let .audio(data):
            if let buffers = pcmBuffers(from: data), !buffers.isEmpty {
                return await graph.play(buffers, allowsBargeIn: graph.voiceProcessing)
            }
        case let .system(text):
            guard !text.isEmpty else { return .finished }
            if let buffers = await systemBuffers(text, language: language), !buffers.isEmpty {
                return await graph.play(buffers, allowsBargeIn: graph.voiceProcessing)
            }
        }
        await playOutsideTheGraph(utterance, language: language)
        return .finished
    }

    /// Decoded reply audio in the engine's playback format, so echo cancellation
    /// can hear exactly what is coming out of the speaker.
    private func pcmBuffers(from data: Data) -> [AVAudioPCMBuffer]? {
        guard let playbackFormat = graph.playbackFormat else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("car-tts-\(UUID().uuidString).\(Self.audioExtension(for: data))")
        do {
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let file = try AVAudioFile(forReading: url)
            guard let converter = AVAudioConverter(from: file.processingFormat, to: playbackFormat) else {
                return nil
            }
            var buffers: [AVAudioPCMBuffer] = []
            while file.framePosition < file.length {
                guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else {
                    return nil
                }
                try file.read(into: input)
                if input.frameLength == 0 { break }
                let ratio = playbackFormat.sampleRate / file.processingFormat.sampleRate
                let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
                guard let output = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: capacity) else {
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
                    return input
                }
                guard error == nil, output.frameLength > 0 else { return nil }
                buffers.append(output)
            }
            return buffers
        } catch {
            return nil
        }
    }

    /// System-voice audio rendered into buffers. The synthesizer signals the
    /// end with an empty buffer.
    private func systemBuffers(_ text: String, language: String) async -> [AVAudioPCMBuffer]? {
        let rendered: [AVAudioPCMBuffer] = await withCheckedContinuation { continuation in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: language)
            var buffers: [AVAudioPCMBuffer] = []
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    continuation.resume(returning: buffers)
                    return
                }
                if let copy = VoiceAudioGraph.copy(pcm) {
                    buffers.append(copy)
                }
            }
        }
        let converted = rendered.compactMap { graph.converted($0) }
        return converted.isEmpty ? nil : converted
    }

    /// Playback the echo canceller cannot see. Barge-in stays off for it.
    private func playOutsideTheGraph(_ utterance: Utterance, language: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playbackContinuation = continuation
            switch utterance {
            case let .audio(data):
                guard let player = try? AVAudioPlayer(data: data) else {
                    resumePlayback()
                    return
                }
                self.player = player
                player.delegate = self
                if !player.play() {
                    resumePlayback()
                }
            case let .system(text):
                guard !text.isEmpty else {
                    resumePlayback()
                    return
                }
                let speech = AVSpeechUtterance(string: text)
                speech.voice = AVSpeechSynthesisVoice(language: language)
                synthesizer.speak(speech)
            }
        }
    }

    private func resumePlayback() {
        let continuation = playbackContinuation
        playbackContinuation = nil
        continuation?.resume()
    }
}

extension SpeechOutput: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resumePlayback() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.resumePlayback() }
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumePlayback() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumePlayback() }
    }
}

/// Short generated tones that tell the driver, without looking, when the
/// microphone opens, when Synaplan is working, and when something went wrong.
@MainActor
final class AudioCues {
    enum Cue {
        case listening
        case thinking
        case ended
        case error
    }

    private var player: AVAudioPlayer?
    private lazy var tones: [Cue: Data] = [
        .listening: Self.wav(frequencies: [660, 880], toneDuration: 0.09),
        .thinking: Self.wav(frequencies: [520], toneDuration: 0.07),
        .ended: Self.wav(frequencies: [880, 660], toneDuration: 0.09),
        .error: Self.wav(frequencies: [330, 247], toneDuration: 0.14),
    ]

    func play(_ cue: Cue) async {
        guard let data = tones[cue], let player = try? AVAudioPlayer(data: data) else { return }
        self.player = player
        player.play()
        try? await Task.sleep(nanoseconds: UInt64(player.duration * 1_000_000_000))
    }

    /// 16-bit mono PCM WAV with a short fade per tone to avoid clicks.
    static func wav(frequencies: [Double], toneDuration: Double, sampleRate: Double = 44_100) -> Data {
        var samples: [Int16] = []
        let perTone = Int(toneDuration * sampleRate)
        let fade = max(1, perTone / 8)
        for frequency in frequencies {
            for index in 0 ..< perTone {
                let envelope = min(1, Double(min(index, perTone - index)) / Double(fade))
                let value = sin(2 * .pi * frequency * Double(index) / sampleRate) * envelope * 0.35
                samples.append(Int16(value * Double(Int16.max)))
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: MemoryLayout<T>.size))
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(Data("RIFF".utf8))
        append(UInt32(36) + byteCount)
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(Data("data".utf8))
        append(byteCount)
        for sample in samples {
            append(sample)
        }
        return data
    }
}
