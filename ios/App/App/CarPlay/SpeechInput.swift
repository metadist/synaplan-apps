import AVFoundation
import Foundation
import Speech

enum SpeechInputError: Error {
    case microphoneDenied
    case unavailable
}

/// One listening turn: returns the transcript, or nil when nothing was said.
protocol SpeechInput: AnyObject {
    func listen(language: String) async throws -> String?
}

/// CarPlay only reads these states. A permission prompt would appear on the
/// iPhone, which the driver must never be asked to touch, so prompts happen
/// on the phone through `CarPermissionPrompt` instead.
enum SpeechPermissions {
    enum Status {
        case granted
        case denied
        case undetermined
    }

    static var microphone: Status {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .undetermined: return .undetermined
            default: return .denied
            }
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return .granted
        case .undetermined: return .undetermined
        default: return .denied
        }
    }

    static var speechRecognition: Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    static func requestMicrophone() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    static func requestSpeechRecognition() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}

/// Remembers that CarPlay needed a permission nobody has been asked for yet,
/// and asks for it the next time Synaplan is in the foreground on the iPhone.
enum CarPermissionPrompt {
    private static let pendingKey = "com.synaplan.carplay.permissionsPending"

    static func markPending() {
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    static func requestIfPending() {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        Task {
            if SpeechPermissions.microphone == .undetermined {
                _ = await SpeechPermissions.requestMicrophone()
            }
            if SpeechPermissions.speechRecognition == .undetermined {
                _ = await SpeechPermissions.requestSpeechRecognition()
            }
        }
    }
}

/// Runs the microphone until the endpointer decides, handing every buffer to
/// `onBuffer`. Cancelling the calling task stops the capture immediately.
final class MicrophoneCapture {
    enum Outcome {
        case speech
        case noSpeech
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var endpointer = UtteranceEndpointer()
    private var continuation: CheckedContinuation<Outcome, Error>?
    private var startTime: TimeInterval = 0

    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func noteTranscriptProgress() {
        lock.lock()
        endpointer.noteTranscriptProgress(at: ProcessInfo.processInfo.systemUptime - startTime)
        lock.unlock()
    }

    func run(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) async throws -> Outcome {
        let format = inputFormat
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechInputError.unavailable }
        startTime = ProcessInfo.processInfo.systemUptime

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    guard let self else { return }
                    onBuffer(buffer)
                    let level = buffer.floatChannelData.map {
                        UtteranceEndpointer.levelDb(samples: $0[0], count: Int(buffer.frameLength))
                    } ?? -160
                    self.lock.lock()
                    let decision = self.endpointer.feed(
                        levelDb: level,
                        at: ProcessInfo.processInfo.systemUptime - self.startTime
                    )
                    self.lock.unlock()
                    switch decision {
                    case .keepListening: break
                    case .utteranceEnded: self.finish(.success(.speech))
                    case .noSpeech: self.finish(.success(.noSpeech))
                    }
                }
                do {
                    engine.prepare()
                    try engine.start()
                } catch {
                    finish(.failure(SpeechInputError.unavailable))
                }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<Outcome, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        pending.resume(with: result)
    }
}

/// On-device recognition with `SpeechAnalyzer` (iOS 26+). Nothing leaves the
/// phone until the final transcript is sent as the chat message.
@available(iOS 26.0, *)
final class OnDeviceSpeechInput: SpeechInput {
    /// True when the locale is supported and its model is already installed.
    static func isReady(language: String) async -> Bool {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            return false
        }
        return await AssetInventory.status(forModules: [transcriber(for: locale)]) == .installed
    }

    /// Downloads the model in the background so the next conversation can
    /// recognize on-device; the current one uses the server meanwhile.
    static func prepare(language: String) {
        Task.detached(priority: .utility) {
            guard SpeechTranscriber.isAvailable,
                  let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)),
                  let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber(for: locale)]) else {
                return
            }
            try? await request.downloadAndInstall()
        }
    }

    private static func transcriber(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    func listen(language: String) async throws -> String? {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw SpeechInputError.unavailable
        }
        let transcriber = Self.transcriber(for: locale)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechInputError.unavailable
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let capture = MicrophoneCapture()
        guard let converter = AVAudioConverter(from: capture.inputFormat, to: analyzerFormat) else {
            throw SpeechInputError.unavailable
        }

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let transcript = TranscriptAccumulator()
        try await analyzer.start(inputSequence: inputStream)

        let resultsTask = Task {
            for try await result in transcriber.results {
                transcript.add(String(result.text.characters), isFinal: result.isFinal)
                capture.noteTranscriptProgress()
            }
        }

        let outcome: MicrophoneCapture.Outcome
        do {
            outcome = try await capture.run { buffer in
                if let converted = Self.convert(buffer, with: converter, to: analyzerFormat) {
                    inputContinuation.yield(AnalyzerInput(buffer: converted))
                }
            }
        } catch {
            inputContinuation.finish()
            await analyzer.cancelAndFinishNow()
            resultsTask.cancel()
            throw error
        }

        inputContinuation.finish()
        if outcome == .noSpeech, transcript.text.isEmpty {
            await analyzer.cancelAndFinishNow()
            resultsTask.cancel()
            return nil
        }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        _ = try? await resultsTask.value
        let text = transcript.text
        return text.isEmpty ? nil : text
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
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
        return error == nil && output.frameLength > 0 ? output : nil
    }
}

/// Keeps finalized segments plus the latest volatile hypothesis.
private final class TranscriptAccumulator {
    private let lock = NSLock()
    private var finalized = ""
    private var volatile = ""

    func add(_ segment: String, isFinal: Bool) {
        lock.lock()
        if isFinal {
            finalized += segment
            volatile = ""
        } else {
            volatile = segment
        }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Fallback: records the utterance locally and lets the Synaplan server
/// transcribe it (`purpose=dictation`, nothing is stored server-side).
final class ServerSpeechInput: SpeechInput {
    private let client: SynaplanCarClient

    init(client: SynaplanCarClient) {
        self.client = client
    }

    func listen(language: String) async throws -> String? {
        let capture = MicrophoneCapture()
        let format = capture.inputFormat
        let fileUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("car-dictation-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: fileUrl) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        var file: AVAudioFile? = try AVAudioFile(
            forWriting: fileUrl,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let outcome = try await capture.run { buffer in
            try? file?.write(from: buffer)
        }
        file = nil
        guard outcome == .speech else { return nil }
        let text = try await client.transcribe(audioFile: fileUrl)
        return text.isEmpty ? nil : text
    }
}
