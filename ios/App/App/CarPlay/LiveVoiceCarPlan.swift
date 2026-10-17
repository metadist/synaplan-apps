import Foundation

/// What CarPlay does at the start of a conversation, and when a live socket ends.
///
/// Live runs only when the server says it is available, the driver has allowed
/// it, and the monthly budget is not already used up. A used-up budget ends
/// the conversation after one spoken sentence. A busy or down live service
/// speaks one sentence and continues with the turn-based loop in the same chat.
enum LiveVoiceSentence: String, Equatable {
    case budget = "voice.liveBudget"
    case busy = "voice.liveBusy"
    case down = "voice.liveDown"
    case networkLost = "voice.liveNetwork"
}

enum LiveVoiceRoute: Equatable {
    case turnBased
    case startLive
    case endBudget
    case speakThenTurnBased(LiveVoiceSentence)
}

enum LiveVoiceStop: Equatable {
    case quiet
    case idle
    case budget
    case network
    case failed
    case turnBased(LiveVoiceSentence)
}

struct LiveVoiceOptions: Equatable {
    var available: Bool
    var budgetExhausted: Bool
    var consentGiven: Bool
}

struct LiveVoiceStart: Equatable {
    var sessionId: Int
    var chatId: Int?
    var ticket: String
    var wsUrl: String
    var inRate: Int
    var outRate: Int
    var transport: String
}

/// What moves the car's phase title. The relay only marks thinking. Speaking
/// and listening come from the reply audio, the same way as on the phone.
enum LiveVoiceSignal: Equatable {
    case ready
    case state(String)
    case audio
    case playbackIdle
    case interrupted
    case wrapUp
}

enum LiveVoiceFrame: Equatable {
    case ready
    case state(String)
    case interrupted
    case wrapUp
    case ended(String)
    case ignored
}

enum LiveVoiceCarPlan {
    /// The gateway keeps a CarPlay provider session this long after the socket drops.
    static let reconnectWindow: TimeInterval = 20

    static func route(for options: LiveVoiceOptions) -> LiveVoiceRoute {
        if options.budgetExhausted { return .endBudget }
        if options.available && options.consentGiven { return .startLive }
        return .turnBased
    }

    static func route(status: Int, code: String) -> LiveVoiceRoute {
        if status == 429 || code == "COST_BUDGET_EXCEEDED" { return .endBudget }
        if status == 403 || code == "VOICE_CONSENT_REQUIRED" { return .turnBased }
        if status == 409 || code == "VOICE_BUSY" || code == "VOICE_CAPACITY" {
            return .speakThenTurnBased(.busy)
        }
        if status == 503 || code == "VOICE_UNAVAILABLE" {
            return .speakThenTurnBased(.down)
        }
        return .speakThenTurnBased(.down)
    }

    static func route(for start: LiveVoiceStart) -> LiveVoiceRoute {
        if start.transport == "relay", start.wsUrl.hasPrefix("ws") { return .startLive }
        return .speakThenTurnBased(.down)
    }

    static func stop(for reason: String) -> LiveVoiceStop {
        switch reason {
        case "limit_budget": return .budget
        case "capacity": return .turnBased(.busy)
        case "provider_error", "admin_disabled": return .turnBased(.down)
        case "network_lost": return .network
        case "idle": return .idle
        case "user_end", "max_duration": return .quiet
        default: return .failed
        }
    }

    static func reconnectOpen(since drop: Date, now: Date) -> Bool {
        now.timeIntervalSince(drop) < reconnectWindow
    }

    static func options(from data: Data) -> LiveVoiceOptions {
        let object = jsonObject(data)
        return LiveVoiceOptions(
            available: object?["available"] as? Bool ?? false,
            budgetExhausted: object?["budgetExhausted"] as? Bool ?? false,
            consentGiven: object?["consentGiven"] as? Bool ?? false
        )
    }

    static func errorCode(from data: Data) -> String {
        let object = jsonObject(data)
        return object?["code"] as? String ?? ""
    }

    static func start(from data: Data) throws -> LiveVoiceStart {
        guard let object = jsonObject(data),
              let sessionId = intValue(object["sessionId"]),
              let ticket = object["ticket"] as? String, !ticket.isEmpty,
              let wsUrl = object["wsUrl"] as? String, !wsUrl.isEmpty,
              let audio = object["audio"] as? [String: Any],
              let inRate = intValue(audio["inRate"]), inRate > 0,
              let outRate = intValue(audio["outRate"]), outRate > 0 else {
            throw CarClientError.failed
        }
        return LiveVoiceStart(
            sessionId: sessionId,
            chatId: intValue(object["chatId"]),
            ticket: ticket,
            wsUrl: wsUrl,
            inRate: inRate,
            outRate: outRate,
            transport: object["transport"] as? String ?? "relay"
        )
    }

    static func frame(from text: String) -> LiveVoiceFrame {
        guard let data = text.data(using: .utf8),
              let object = jsonObject(data),
              let type = object["type"] as? String else {
            return .ignored
        }
        switch type {
        case "ready": return .ready
        case "state": return .state(object["state"] as? String ?? "listening")
        case "interrupted": return .interrupted
        case "wrap_up": return .wrapUp
        case "ended": return .ended(object["reason"] as? String ?? "provider_error")
        default: return .ignored
        }
    }

    /// Same transitions as a live call on the phone. A reply stays "answering"
    /// until its audio has drained, and thinking is not replaced by that drain.
    static func phase(after current: LiveVoicePhase, signal: LiveVoiceSignal) -> LiveVoicePhase {
        switch signal {
        case .wrapUp:
            return .ending
        case .ready:
            return .listening
        case let .state(name):
            if current == .ending { return .ending }
            if name == "thinking" { return .thinking }
            if name == "speaking" { return .speaking }
            return .listening
        case .audio:
            return current == .ending ? .ending : .speaking
        case .playbackIdle:
            return current == .speaking ? .listening : current
        case .interrupted:
            return current == .ending ? .ending : .listening
        }
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber, !(value is Bool) { return number.intValue }
        return nil
    }
}

/// Phases that decide a cue. Same set the chat uses, including the ones that
/// stay silent (`speaking`, `ending`).
enum LiveVoicePhase: Equatable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case ending
    case ended
}

enum LiveVoiceCue: Equatable {
    case open
    case ready
    case ask
    case end
    case fail
}

/// Why the car conversation stopped, reduced to the two closing tones.
enum LiveVoiceEnding: Equatable {
    case userEnded
    case idle
    case budget
    case networkLost
    case failed
}

struct LiveVoiceCueStep: Equatable {
    var frequency: Double
    var toFrequency: Double?
    var duration: Double
}

/// One tone per moment, matching `liveCueForTransition` in the chat.
///
/// Rising means the line is opening, falling means it is closing. Speaking
/// and a return to listening stay silent: the voices are already the sound.
/// The phone plays these near a gain of 0.05. In the car they use the level
/// the turn tones already had, so they stay audible over road noise.
enum LiveVoiceCuePlan {
    static let askGap: TimeInterval = 0.9
    /// Silence between the notes of one cue, matching the chat.
    static let stepGap: TimeInterval = 0.045
    static let cabinGain: Double = 0.35

    static let failures: Set<String> = [
        "provider_error",
        "network_lost",
        "capacity",
        "mic_denied",
        "admin_disabled",
    ]

    static func cue(previous: LiveVoicePhase?, next: LiveVoicePhase, reason: String = "") -> LiveVoiceCue? {
        guard let previous, previous != next else { return nil }
        if next == .connecting, previous == .idle || previous == .ended { return .open }
        if next == .listening, previous == .connecting { return .ready }
        if next == .thinking { return .ask }
        if next == .idle, previous != .ended { return .end }
        if next == .ended { return failures.contains(reason) ? .fail : .end }
        return nil
    }

    static func endingCue(for ending: LiveVoiceEnding) -> LiveVoiceCue {
        switch ending {
        case .userEnded, .idle, .budget:
            return .end
        case .networkLost, .failed:
            return .fail
        }
    }

    static func allowsAsk(now: Date, lastAsk: Date?) -> Bool {
        guard let lastAsk else { return true }
        return now.timeIntervalSince(lastAsk) >= askGap
    }

    /// Ask overlaps an open microphone. Skip it when the reply is already
    /// playing, or when echo cancellation cannot take the tone back out.
    static func shouldPlayAsk(voiceProcessing: Bool, playbackBusy: Bool, now: Date, lastAsk: Date?) -> Bool {
        voiceProcessing && !playbackBusy && allowsAsk(now: now, lastAsk: lastAsk)
    }

    static func steps(for cue: LiveVoiceCue) -> [LiveVoiceCueStep] {
        switch cue {
        case .open:
            return [
                LiveVoiceCueStep(frequency: 392, toFrequency: nil, duration: 0.08),
                LiveVoiceCueStep(frequency: 523.25, toFrequency: nil, duration: 0.13),
            ]
        case .ready:
            return [
                LiveVoiceCueStep(frequency: 523.25, toFrequency: nil, duration: 0.07),
                LiveVoiceCueStep(frequency: 659.25, toFrequency: nil, duration: 0.15),
            ]
        case .ask:
            return [
                LiveVoiceCueStep(frequency: 440, toFrequency: 659.25, duration: 0.17),
            ]
        case .fail:
            return [
                LiveVoiceCueStep(frequency: 311, toFrequency: nil, duration: 0.09),
                LiveVoiceCueStep(frequency: 247, toFrequency: nil, duration: 0.15),
            ]
        case .end:
            return [
                LiveVoiceCueStep(frequency: 659.25, toFrequency: nil, duration: 0.07),
                LiveVoiceCueStep(frequency: 392, toFrequency: nil, duration: 0.17),
            ]
        }
    }

    static func duration(for cue: LiveVoiceCue) -> TimeInterval {
        let steps = steps(for: cue)
        let tones = steps.reduce(0) { $0 + $1.duration }
        return tones + stepGap * Double(max(0, steps.count - 1))
    }

    /// Sine tones with a short fade and, for ask, the chat's rising sweep.
    static func samples(for cue: LiveVoiceCue, sampleRate: Double) -> [Float] {
        guard sampleRate > 0 else { return [] }
        let steps = steps(for: cue)
        let gapFrames = Int((stepGap * sampleRate).rounded())
        let fadeFrames = max(1, Int((0.018 * sampleRate).rounded()))
        var samples: [Float] = []
        for (index, step) in steps.enumerated() {
            let frames = max(1, Int((step.duration * sampleRate).rounded()))
            for frame in 0 ..< frames {
                let time = Double(frame) / sampleRate
                let edge = min(frame, frames - 1 - frame)
                let envelope = min(1, Double(edge) / Double(fadeFrames))
                let value = sin(2 * .pi * frequency(of: step, at: time) * time) * envelope * cabinGain
                samples.append(Float(value))
            }
            if index + 1 < steps.count, gapFrames > 0 {
                samples.append(contentsOf: repeatElement(0, count: gapFrames))
            }
        }
        return samples
    }

    private static func frequency(of step: LiveVoiceCueStep, at time: Double) -> Double {
        guard let target = step.toFrequency, target > 0, step.frequency > 0, step.duration > 0 else {
            return step.frequency
        }
        let progress = min(1, max(0, time / step.duration))
        return step.frequency * pow(target / step.frequency, progress)
    }
}

enum PCM16 {
    static func encode(_ samples: [Float]) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { raw in
            let dest = raw.bindMemory(to: Int16.self)
            for (index, sample) in samples.enumerated() {
                let clamped = max(-1, min(1, sample))
                dest[index] = Int16((clamped * 32767).rounded())
            }
        }
        return data
    }

    static func decode(_ data: Data) -> [Float] {
        let count = data.count / 2
        var samples = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let source = raw.bindMemory(to: Int16.self)
            for index in 0 ..< count {
                samples[index] = Float(source[index]) / 32767
            }
        }
        return samples
    }

    /// Linear resample. The live socket wants a fixed rate; the microphone does not.
    static func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard inputRate > 0, outputRate > 0, !samples.isEmpty else { return [] }
        if inputRate == outputRate { return samples }
        let count = max(1, Int((Double(samples.count) * outputRate / inputRate).rounded()))
        var output = [Float](repeating: 0, count: count)
        let scale = inputRate / outputRate
        for index in 0 ..< count {
            let position = Double(index) * scale
            let left = min(Int(position), samples.count - 1)
            let right = min(left + 1, samples.count - 1)
            let fraction = Float(position - Double(left))
            output[index] = samples[left] * (1 - fraction) + samples[right] * fraction
        }
        return output
    }
}
