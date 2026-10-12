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

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber, !(value is Bool) { return number.intValue }
        return nil
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
