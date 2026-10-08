import Foundation

/// Decides when the driver has finished speaking, from the microphone level
/// alone, so the turn ends without a button press.
struct UtteranceEndpointer {
    enum Decision: Equatable {
        case keepListening
        /// Speech was heard and has been followed by enough silence.
        case utteranceEnded
        /// Nothing was said within `noSpeechTimeout`.
        case noSpeech
    }

    /// Level (dBFS) above which a buffer counts as speech.
    var speechThresholdDb: Float = -42
    var silenceAfterSpeech: TimeInterval = 1.4
    var noSpeechTimeout: TimeInterval = 8
    var maximumDuration: TimeInterval = 60

    private(set) var heardSpeech = false
    private var startedAt: TimeInterval?
    private var lastVoiceAt: TimeInterval?

    mutating func feed(levelDb: Float, at time: TimeInterval) -> Decision {
        let start = startedAt ?? time
        startedAt = start
        if levelDb >= speechThresholdDb {
            heardSpeech = true
            lastVoiceAt = time
        }
        return decide(at: time, start: start)
    }

    /// The recognizer produced new words; counts as voice activity even when
    /// the level hovered just below the threshold.
    mutating func noteTranscriptProgress(at time: TimeInterval) {
        heardSpeech = true
        lastVoiceAt = time
    }

    private func decide(at time: TimeInterval, start: TimeInterval) -> Decision {
        if time - start >= maximumDuration {
            return heardSpeech ? .utteranceEnded : .noSpeech
        }
        if let lastVoiceAt, heardSpeech {
            return time - lastVoiceAt >= silenceAfterSpeech ? .utteranceEnded : .keepListening
        }
        return time - start >= noSpeechTimeout ? .noSpeech : .keepListening
    }

    /// RMS level of the first channel in dBFS (floored at -160).
    static func levelDb(samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return -160 }
        var sum: Float = 0
        for index in 0 ..< count {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        return rms > 0 ? max(-160, 20 * log10(rms)) : -160
    }
}
