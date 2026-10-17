@testable import CarPlayLogic
import XCTest

final class CarSessionContractTests: XCTestCase {
    /// Reference values computed with `serverScope()` from `nativeAuth.ts`;
    /// `tests/carplay-contract.test.mjs` recomputes the same vectors in JS.
    func testServerScopeMatchesTheSpaImplementation() {
        XCTAssertEqual(CarSessionContract.serverScope(for: "https://web.synaplan.com"), "1d68gy7")
        XCTAssertEqual(CarSessionContract.serverScope(for: "http://localhost:8000"), "15tgstk")
        XCTAssertEqual(CarSessionContract.serverScope(for: "https://chat.example.test"), "18ac4c8")
        XCTAssertEqual(CarSessionContract.serverScope(for: "https://ünï.example/äpi"), "9no7an")
    }

    func testAppStorageKeysUseTheSecureStoragePrefix() {
        let keys = CarSessionContract.appStorageKeys(for: "https://web.synaplan.com")
        XCTAssertEqual(keys.access, "capacitor-storage_syn_native_at_1d68gy7")
        XCTAssertEqual(keys.refresh, "capacitor-storage_syn_native_rt_1d68gy7")
    }

    func testServerUrlNormalization() {
        XCTAssertEqual(CarSessionContract.normalizedServerUrl("  https://chat.example.test/ "), "https://chat.example.test")
        XCTAssertEqual(CarSessionContract.normalizedServerUrl(nil), "https://web.synaplan.com")
        XCTAssertEqual(CarSessionContract.normalizedServerUrl(""), "https://web.synaplan.com")
    }
}

final class CarAPIDecodingTests: XCTestCase {
    func testChatListSkipsWidgetSessionsAndParsesDates() throws {
        let json = """
        {"success":true,"total":3,"offset":0,"limit":12,"hasMore":false,"chats":[
          {"id":7,"title":" Trip planning ","createdAt":"2026-10-01T08:00:00+02:00","updatedAt":"2026-10-07T18:30:00+02:00","messageCount":4,"isShared":false,"firstMessagePreview":"secret"},
          {"id":8,"title":"Visitor","createdAt":"2026-10-01T08:00:00+00:00","updatedAt":"2026-10-01T08:00:00+00:00","messageCount":1,"isShared":false,"widgetSession":{"widgetId":"w1"}},
          {"id":9,"title":"","createdAt":"x","updatedAt":"bad","messageCount":0,"isShared":false,"widgetSession":null}
        ]}
        """
        let chats = try CarAPIDecoding.chatList(Data(json.utf8))
        XCTAssertEqual(chats.map(\.id), [7, 9])
        XCTAssertEqual(chats[0].title, "Trip planning")
        XCTAssertNotNil(chats[0].updatedAt)
        XCTAssertEqual(chats[1].title, "")
        XCTAssertNil(chats[1].updatedAt)
    }

    func testChatListSkipsChannelChatsAndBlanksPlaceholderTitles() throws {
        let json = """
        {"chats":[
          {"id":1,"title":"Neuer Chat","updatedAt":"2026-10-07T18:30:00+02:00","source":"web"},
          {"id":2,"title":"WhatsApp: +491701234567","updatedAt":"2026-10-07T18:30:00+02:00","source":"whatsapp"},
          {"id":3,"title":"Email: invoice","updatedAt":"2026-10-07T18:30:00+02:00","source":"email"},
          {"id":4,"title":"New Chat","updatedAt":"2026-10-07T18:30:00+02:00","source":null}
        ]}
        """
        let chats = try CarAPIDecoding.chatList(Data(json.utf8))
        XCTAssertEqual(chats.map(\.id), [1, 4])
        XCTAssertEqual(chats.map(\.title), ["", ""])
    }

    func testPinnedChatsComeFirstAndKeepServerOrder() throws {
        let json = """
        {"chats":[
          {"id":1,"title":"Recent","updatedAt":"2026-10-07T18:30:00+02:00","pinned":false},
          {"id":2,"title":"Pinned new","updatedAt":"2026-10-06T18:30:00+02:00","pinned":true},
          {"id":3,"title":"Older","updatedAt":"2026-10-05T18:30:00+02:00"},
          {"id":4,"title":"Pinned old","updatedAt":"2026-10-01T18:30:00+02:00","pinned":true}
        ]}
        """
        let chats = try CarAPIDecoding.chatList(Data(json.utf8))
        XCTAssertEqual(chats.map(\.id), [2, 4, 1, 3])
        XCTAssertEqual(chats.map(\.pinned), [true, true, false, false])
    }

    func testMalformedChatListFails() {
        XCTAssertThrowsError(try CarAPIDecoding.chatList(Data("{\"error\":\"x\"}".utf8)))
    }

    func testCreatedChatAndRefreshAndDictation() throws {
        XCTAssertEqual(try CarAPIDecoding.createdChatId(Data(#"{"success":true,"chat":{"id":42,"title":"New"}}"#.utf8)), 42)
        XCTAssertEqual(CarAPIDecoding.refreshedAccessToken(Data(#"{"success":true,"tokens":{"accessToken":"a.b","refreshToken":"r","expiresIn":300}}"#.utf8)), "a.b")
        XCTAssertNil(CarAPIDecoding.refreshedAccessToken(Data(#"{"success":true}"#.utf8)))
        XCTAssertEqual(try CarAPIDecoding.dictationText(Data(#"{"success":true,"text":" Hello there \n"}"#.utf8)), "Hello there")
        XCTAssertTrue(CarAPIDecoding.serverTranscriptionAvailable(Data(#"{"speech":{"speechToTextAvailable":true}}"#.utf8)))
        XCTAssertFalse(CarAPIDecoding.serverTranscriptionAvailable(Data(#"{"speech":{}}"#.utf8)))
    }

    func testUserAgentMatchesTheBackendPattern() throws {
        let pattern = try NSRegularExpression(pattern: #"Synaplan Mobile V(\d+)\.(\d+)(?:\.(\d+))?"#)
        for version in ["4.0.3", "4", nil, "garbage"] {
            let agent = CarAPIDecoding.userAgent(shortVersion: version)
            let range = NSRange(agent.startIndex..., in: agent)
            XCTAssertNotNil(pattern.firstMatch(in: agent, range: range), agent)
        }
        XCTAssertEqual(CarAPIDecoding.userAgent(shortVersion: "4.0.3"), "Synaplan Mobile V4.0 CarPlay")
    }
}

final class SynaplanStreamParserTests: XCTestCase {
    func testParsesTheEventsTheCarUses() {
        XCTAssertEqual(SynaplanStreamParser.parse(line: #"data: {"status":"data","chunk":"Hi"}"#), .text("Hi"))
        XCTAssertEqual(
            SynaplanStreamParser.parse(line: #"data: {"status":"complete","messageId":1,"chatId":2,"content":"Hi","chatTitle":"Greeting"}"#),
            .complete(content: "Hi", chatTitle: "Greeting")
        )
        XCTAssertEqual(SynaplanStreamParser.parse(line: #"data: {"status":"error","error":"boom"}"#), .failure(message: "boom"))
        XCTAssertEqual(SynaplanStreamParser.parse(line: #"data: {"status":"message","message":"limit"}"#), .limitReached(message: "limit"))
    }

    func testIgnoresEverythingElse() {
        XCTAssertNil(SynaplanStreamParser.parse(line: #"data: {"status":"thinking"}"#))
        XCTAssertNil(SynaplanStreamParser.parse(line: #"data: {"status":"data","chunk":""}"#))
        XCTAssertNil(SynaplanStreamParser.parse(line: ": keep-alive"))
        XCTAssertNil(SynaplanStreamParser.parse(line: "data: not json"))
        XCTAssertNil(SynaplanStreamParser.parse(line: "event: ping"))
    }
}

final class SpokenTextChunkerTests: XCTestCase {
    func testEmitsSentencesAsSoonAsTheyAreComplete() {
        var chunker = SpokenTextChunker()
        XCTAssertEqual(chunker.append("The weather in Berlin is sunny"), [])
        XCTAssertEqual(chunker.append(" today. Tomorrow"), ["The weather in Berlin is sunny today."])
        XCTAssertEqual(chunker.append(" it rains."), [])
        XCTAssertEqual(chunker.finish(), ["Tomorrow it rains."])
    }

    func testMergesVeryShortSentences() {
        var chunker = SpokenTextChunker()
        XCTAssertEqual(chunker.append("Yes. Of course I can help with that. "), ["Yes. Of course I can help with that."])
    }

    func testStripsMarkdownLinksCodeAndMemoryBadges() {
        var chunker = SpokenTextChunker()
        let text = """
        ## Summary
        - **Bold** point with [a link](https://example.com) [Memory:12]
        ```swift
        let secret = 1
        ```
        | a | b |
        |---|---|
        See https://example.com/path for `details`.
        """
        let spoken = chunker.append(text) + chunker.finish()
        XCTAssertEqual(spoken, ["Summary", "Bold point with a link", "See for details."])
    }
}

final class UtteranceEndpointerTests: XCTestCase {
    func testEndsAfterSilenceFollowingSpeech() {
        var endpointer = UtteranceEndpointer()
        XCTAssertEqual(endpointer.feed(levelDb: -60, at: 0), .keepListening)
        XCTAssertEqual(endpointer.feed(levelDb: -20, at: 1), .keepListening)
        XCTAssertEqual(endpointer.feed(levelDb: -60, at: 2), .keepListening)
        XCTAssertEqual(endpointer.feed(levelDb: -60, at: 2.5), .utteranceEnded)
    }

    func testReportsNoSpeechAfterTimeout() {
        var endpointer = UtteranceEndpointer()
        XCTAssertEqual(endpointer.feed(levelDb: -70, at: 0), .keepListening)
        XCTAssertEqual(endpointer.feed(levelDb: -70, at: 7.9), .keepListening)
        XCTAssertEqual(endpointer.feed(levelDb: -70, at: 8), .noSpeech)
    }

    func testTranscriptProgressCountsAsVoice() {
        var endpointer = UtteranceEndpointer()
        XCTAssertEqual(endpointer.feed(levelDb: -70, at: 0), .keepListening)
        endpointer.noteTranscriptProgress(at: 5)
        XCTAssertEqual(endpointer.feed(levelDb: -70, at: 6), .keepListening)
        XCTAssertEqual(endpointer.feed(levelDb: -70, at: 6.5), .utteranceEnded)
    }

    func testBargeInNeedsSustainedSpeechAfterCalibration() {
        var detector = BargeInDetector()
        XCTAssertFalse(detector.feed(levelDb: -55, at: 0.1))
        XCTAssertFalse(detector.feed(levelDb: -60, at: 0.5))
        XCTAssertFalse(detector.feed(levelDb: -10, at: 0.9))
        XCTAssertFalse(detector.feed(levelDb: -10, at: 1.2))
        XCTAssertTrue(detector.feed(levelDb: -10, at: 1.3))
    }

    func testBargeInIgnoresTheReplyLeakingIntoTheMicrophone() {
        var detector = BargeInDetector()
        XCTAssertFalse(detector.feed(levelDb: -24, at: 0.2))
        XCTAssertFalse(detector.feed(levelDb: -28, at: 0.6))
        for step in 0 ..< 30 {
            XCTAssertFalse(detector.feed(levelDb: -14, at: 0.9 + Double(step) * 0.1))
        }
        XCTAssertFalse(detector.feed(levelDb: -8, at: 4.0))
        XCTAssertTrue(detector.feed(levelDb: -8, at: 4.4))
    }

    func testBargeInIgnoresAShortNoiseSpike() {
        var detector = BargeInDetector()
        XCTAssertFalse(detector.feed(levelDb: -60, at: 0.2))
        XCTAssertFalse(detector.feed(levelDb: -10, at: 0.9))
        XCTAssertFalse(detector.feed(levelDb: -80, at: 1.0))
        XCTAssertFalse(detector.feed(levelDb: -10, at: 1.1))
        XCTAssertFalse(detector.feed(levelDb: -10, at: 1.4))
    }

    func testLevelOfSilenceAndFullScale() {
        let silence = [Float](repeating: 0, count: 64)
        let full = [Float](repeating: 1, count: 64)
        XCTAssertEqual(silence.withUnsafeBufferPointer { UtteranceEndpointer.levelDb(samples: $0.baseAddress!, count: 64) }, -160)
        XCTAssertEqual(full.withUnsafeBufferPointer { UtteranceEndpointer.levelDb(samples: $0.baseAddress!, count: 64) }, 0, accuracy: 0.001)
    }
}

final class LiveVoiceCarPlanTests: XCTestCase {
    func testRouteUsesLiveOnlyWithConsentAndBudget() {
        XCTAssertEqual(LiveVoiceCarPlan.route(for: LiveVoiceOptions(available: true, budgetExhausted: false, consentGiven: true)), .startLive)
        XCTAssertEqual(LiveVoiceCarPlan.route(for: LiveVoiceOptions(available: true, budgetExhausted: false, consentGiven: false)), .turnBased)
        XCTAssertEqual(LiveVoiceCarPlan.route(for: LiveVoiceOptions(available: false, budgetExhausted: false, consentGiven: true)), .turnBased)
        XCTAssertEqual(LiveVoiceCarPlan.route(for: LiveVoiceOptions(available: true, budgetExhausted: true, consentGiven: true)), .endBudget)
    }

    func testHttpStatusPicksBudgetBusyOrDown() {
        XCTAssertEqual(LiveVoiceCarPlan.route(status: 429, code: "COST_BUDGET_EXCEEDED"), .endBudget)
        XCTAssertEqual(LiveVoiceCarPlan.route(status: 403, code: "VOICE_CONSENT_REQUIRED"), .turnBased)
        XCTAssertEqual(LiveVoiceCarPlan.route(status: 409, code: "VOICE_BUSY"), .speakThenTurnBased(.busy))
        XCTAssertEqual(LiveVoiceCarPlan.route(status: 503, code: "VOICE_CAPACITY"), .speakThenTurnBased(.busy))
        XCTAssertEqual(LiveVoiceCarPlan.route(status: 503, code: "VOICE_UNAVAILABLE"), .speakThenTurnBased(.down))
        XCTAssertEqual(LiveVoiceCarPlan.route(status: 500, code: ""), .speakThenTurnBased(.down))
    }

    func testStartRequiresTheRelaySocket() {
        let relay = LiveVoiceStart(sessionId: 4, chatId: 9, ticket: "t", wsUrl: "wss://example.test/voice/ws?ticket=t", inRate: 24000, outRate: 24000, transport: "relay")
        XCTAssertEqual(LiveVoiceCarPlan.route(for: relay), .startLive)
        var direct = relay
        direct.transport = "webrtc"
        XCTAssertEqual(LiveVoiceCarPlan.route(for: direct), .speakThenTurnBased(.down))
    }

    func testStopReasons() {
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "limit_budget"), .budget)
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "capacity"), .turnBased(.busy))
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "provider_error"), .turnBased(.down))
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "admin_disabled"), .turnBased(.down))
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "network_lost"), .network)
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "idle"), .idle)
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "user_end"), .quiet)
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "max_duration"), .quiet)
        XCTAssertEqual(LiveVoiceCarPlan.stop(for: "nope"), .failed)
    }

    func testReconnectWindowIsTwentySeconds() {
        XCTAssertEqual(LiveVoiceCarPlan.reconnectWindow, 20)
        let drop = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(LiveVoiceCarPlan.reconnectOpen(since: drop, now: drop.addingTimeInterval(19.9)))
        XCTAssertFalse(LiveVoiceCarPlan.reconnectOpen(since: drop, now: drop.addingTimeInterval(20)))
    }

    func testDecodesOptionsStartAndFrames() throws {
        let options = LiveVoiceCarPlan.options(from: Data(#"{"available":true,"budgetExhausted":false,"consentGiven":true}"#.utf8))
        XCTAssertEqual(options, LiveVoiceOptions(available: true, budgetExhausted: false, consentGiven: true))
        XCTAssertEqual(LiveVoiceCarPlan.errorCode(from: Data(#"{"code":"VOICE_BUSY"}"#.utf8)), "VOICE_BUSY")
        let start = try LiveVoiceCarPlan.start(from: Data(#"{"sessionId":4,"chatId":9,"ticket":"abc","wsUrl":"wss://h/voice/ws?ticket=abc","transport":"relay","audio":{"inRate":16000,"outRate":24000}}"#.utf8))
        XCTAssertEqual(start.sessionId, 4)
        XCTAssertEqual(start.chatId, 9)
        XCTAssertEqual(start.inRate, 16000)
        XCTAssertEqual(LiveVoiceCarPlan.frame(from: #"{"type":"ended","reason":"limit_budget"}"#), .ended("limit_budget"))
        XCTAssertEqual(LiveVoiceCarPlan.frame(from: #"{"type":"wrap_up"}"#), .wrapUp)
        XCTAssertEqual(LiveVoiceCarPlan.frame(from: "nope"), .ignored)
        XCTAssertThrowsError(try LiveVoiceCarPlan.start(from: Data(#"{"sessionId":1}"#.utf8)))
    }

    func testPcm16RoundTripAndResample() {
        let samples: [Float] = [0, 0.5, -1, 1]
        let decoded = PCM16.decode(PCM16.encode(samples))
        XCTAssertEqual(decoded.count, samples.count)
        for (got, want) in zip(decoded, samples) {
            XCTAssertEqual(got, want, accuracy: 0.001)
        }
        let same = PCM16.resample([0.25, -0.25], from: 16000, to: 16000)
        XCTAssertEqual(same, [0.25, -0.25])
        let stretched = PCM16.resample([0, 1], from: 16000, to: 32000)
        XCTAssertEqual(stretched.count, 4)
        XCTAssertEqual(stretched[0], 0, accuracy: 0.001)
        XCTAssertEqual(stretched[3], 1, accuracy: 0.001)
    }

    func testTitleFollowsTheReplyAndReturnsWhenItFinishes() {
        var phase = LiveVoicePhase.connecting
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .ready)
        XCTAssertEqual(phase, .listening)
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .audio)
        XCTAssertEqual(phase, .speaking)
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .audio)
        XCTAssertEqual(phase, .speaking)
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .playbackIdle)
        XCTAssertEqual(phase, .listening)

        phase = LiveVoiceCarPlan.phase(after: phase, signal: .state("thinking"))
        XCTAssertEqual(phase, .thinking)
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .playbackIdle)
        XCTAssertEqual(phase, .thinking)
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .audio)
        XCTAssertEqual(phase, .speaking)

        phase = LiveVoiceCarPlan.phase(after: phase, signal: .wrapUp)
        XCTAssertEqual(phase, .ending)
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .audio)
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .playbackIdle)
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .state("listening"))
        XCTAssertEqual(phase, .ending)

        phase = .speaking
        phase = LiveVoiceCarPlan.phase(after: phase, signal: .interrupted)
        XCTAssertEqual(phase, .listening)
    }
}

final class LiveVoiceCuePlanTests: XCTestCase {
    func testCueMomentsMatchTheChat() {
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .idle, next: .connecting), .open)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .ended, next: .connecting), .open)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .connecting, next: .listening), .ready)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .listening, next: .thinking), .ask)
        XCTAssertNil(LiveVoiceCuePlan.cue(previous: .thinking, next: .speaking))
        XCTAssertNil(LiveVoiceCuePlan.cue(previous: .speaking, next: .listening))
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .listening, next: .idle), .end)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .connecting, next: .ended, reason: "provider_error"), .fail)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .listening, next: .ended, reason: "limit_budget"), .end)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .listening, next: .ended, reason: "user_end"), .end)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .listening, next: .ended, reason: "max_duration"), .end)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .listening, next: .ended, reason: "network_lost"), .fail)
        XCTAssertEqual(LiveVoiceCuePlan.cue(previous: .listening, next: .ended, reason: "mic_denied"), .fail)
        XCTAssertNil(LiveVoiceCuePlan.cue(previous: .listening, next: .listening))
        XCTAssertNil(LiveVoiceCuePlan.cue(previous: nil, next: .connecting))
        XCTAssertNil(LiveVoiceCuePlan.cue(previous: .listening, next: .connecting))
    }

    func testAskGapAndCabinGate() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(LiveVoiceCuePlan.allowsAsk(now: now, lastAsk: nil))
        XCTAssertFalse(LiveVoiceCuePlan.allowsAsk(now: now, lastAsk: now.addingTimeInterval(-0.5)))
        XCTAssertTrue(LiveVoiceCuePlan.allowsAsk(now: now, lastAsk: now.addingTimeInterval(-0.91)))
        XCTAssertFalse(LiveVoiceCuePlan.shouldPlayAsk(voiceProcessing: false, playbackBusy: false, now: now, lastAsk: nil))
        XCTAssertFalse(LiveVoiceCuePlan.shouldPlayAsk(voiceProcessing: true, playbackBusy: true, now: now, lastAsk: nil))
        XCTAssertTrue(LiveVoiceCuePlan.shouldPlayAsk(voiceProcessing: true, playbackBusy: false, now: now, lastAsk: nil))
    }

    func testEndingCues() {
        XCTAssertEqual(LiveVoiceCuePlan.endingCue(for: .userEnded), .end)
        XCTAssertEqual(LiveVoiceCuePlan.endingCue(for: .idle), .end)
        XCTAssertEqual(LiveVoiceCuePlan.endingCue(for: .budget), .end)
        XCTAssertEqual(LiveVoiceCuePlan.endingCue(for: .networkLost), .fail)
        XCTAssertEqual(LiveVoiceCuePlan.endingCue(for: .failed), .fail)
    }

    func testCueStepsMatchTheChat() {
        XCTAssertEqual(LiveVoiceCuePlan.steps(for: .open).map(\.frequency), [392, 523.25])
        XCTAssertEqual(LiveVoiceCuePlan.steps(for: .open).map(\.duration), [0.08, 0.13])
        XCTAssertEqual(LiveVoiceCuePlan.steps(for: .ready).map(\.frequency), [523.25, 659.25])
        let ask = LiveVoiceCuePlan.steps(for: .ask)
        XCTAssertEqual(ask.first?.frequency, 440)
        XCTAssertEqual(ask.first?.toFrequency, 659.25)
        XCTAssertEqual(ask.first?.duration, 0.17)
        XCTAssertEqual(LiveVoiceCuePlan.steps(for: .end).map(\.frequency), [659.25, 392])
        XCTAssertEqual(LiveVoiceCuePlan.steps(for: .fail).map(\.frequency), [311, 247])
    }

    func testCueSamplesStayInsideTheCabinLevelAndAskRises() {
        let rate = 8_000.0
        let open = LiveVoiceCuePlan.samples(for: .open, sampleRate: rate)
        XCTAssertEqual(open.count, Int((LiveVoiceCuePlan.duration(for: .open) * rate).rounded()))
        let peak = open.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertLessThanOrEqual(peak, Float(LiveVoiceCuePlan.cabinGain) + 0.001)

        let ask = LiveVoiceCuePlan.samples(for: .ask, sampleRate: rate)
        let window = 400
        XCTAssertGreaterThan(Self.crossings(Array(ask.suffix(window))), Self.crossings(Array(ask.prefix(window))))
    }

    private static func crossings(_ samples: [Float]) -> Int {
        var count = 0
        for index in 1 ..< samples.count where samples[index - 1] <= 0 && samples[index] > 0 {
            count += 1
        }
        return count
    }
}

final class PcmPlaybackStreamTests: XCTestCase {
    private let sourceRate = 24_000.0

    func testOneSignalSoundsTheSameInOneChunkOrMany() {
        let pcm = Self.ramp(4000)
        for deviceRate in [48_000.0, 44_100.0] {
            let whole = play([pcm], deviceRate: deviceRate)
            for size in [1, 17, 128] {
                sameSamples(whole, play(Self.chunks(of: pcm, size: size), deviceRate: deviceRate))
            }
        }
    }

    func testSplitSignalHasNoSilenceInsideIt() {
        let out = play(Self.chunks(of: Self.ramp(4000), size: 10), deviceRate: 48_000)
        var ended = false
        for sample in out {
            if sample == 0 {
                ended = true
            } else {
                XCTAssertFalse(ended)
            }
        }
        XCTAssertTrue(ended)
    }

    func testPrebufferHoldsAShortTurnUntilItEnds() {
        let deviceRate = 48_000.0
        let below = Array(repeating: Int16(16_000), count: Int(sourceRate * PcmPlaybackStream.prebufferSeconds) - 100)
        let waiting = PcmPlaybackStream()
        waiting.config(sourceRate)
        waiting.push(pcm: below)
        let silent = render(waiting, count: Int(deviceRate * PcmPlaybackStream.startStallSeconds) - 1, deviceRate: deviceRate)
        XCTAssertTrue(silent.allSatisfy { $0 == 0 })

        waiting.push(pcm: Array(repeating: Int16(16_000), count: 200))
        let started = render(waiting, count: 480, deviceRate: deviceRate)
        XCTAssertTrue(started.contains { $0 != 0 })

        let short = PcmPlaybackStream()
        short.config(sourceRate)
        short.push(pcm: below)
        short.endTurn()
        let played = render(short, count: 480, deviceRate: deviceRate)
        XCTAssertTrue(played.contains { $0 != 0 })
    }

    func testUnderrunFadesInsteadOfClicking() {
        let deviceRate = 48_000.0
        let samples = Int((sourceRate * PcmPlaybackStream.prebufferSeconds).rounded(.up))
        let stream = PcmPlaybackStream()
        stream.config(sourceRate)
        stream.push(pcm: Array(repeating: Int16(16_000), count: samples))
        let out = render(
            stream,
            count: Int((Double(samples) * deviceRate / sourceRate).rounded(.up)) + 2000,
            deviceRate: deviceRate
        )

        var peak: Float = 0
        var loudAt = 0
        for index in out.indices where abs(out[index]) > peak {
            peak = abs(out[index])
            loudAt = index
        }
        XCTAssertGreaterThan(peak, 0.4)
        let tail = Array(out.suffix(from: loudAt))
        let silentAt = tail.firstIndex(where: { $0 == 0 }) ?? -1
        XCTAssertGreaterThan(silentAt, Int(deviceRate * 0.004))
        if silentAt > 1 {
            for index in 1 ..< silentAt {
                XCTAssertLessThanOrEqual(tail[index], tail[index - 1] + 0.000001)
            }
        }
        var biggestStep: Float = 0
        for index in 1 ..< out.count {
            biggestStep = max(biggestStep, abs(out[index] - out[index - 1]))
        }
        XCTAssertLessThan(biggestStep, 0.02)
    }

    func testIdleFiresOnceAfterTheReplyDrains() {
        let deviceRate = 48_000.0
        let samples = Int((sourceRate * PcmPlaybackStream.prebufferSeconds).rounded(.up))
        let stream = PcmPlaybackStream()
        stream.config(sourceRate)
        stream.push(pcm: Array(repeating: Int16(8_000), count: samples))
        let played = Int((Double(samples) * deviceRate / sourceRate).rounded(.up))
        let settle = played + Int(deviceRate * 0.35)
        _ = render(stream, count: settle, deviceRate: deviceRate)
        XCTAssertTrue(stream.takeIdle())
        XCTAssertFalse(stream.takeIdle())
        XCTAssertFalse(stream.isOutputActive)

        stream.push(pcm: Array(repeating: Int16(8_000), count: samples))
        XCTAssertFalse(stream.takeIdle())
        XCTAssertTrue(stream.isOutputActive)
    }

    func testFlushDropsTheBufferAndTheNextTurnStartsClean() {
        let deviceRate = 48_000.0
        let pcm = Self.ramp(4000)
        let stream = PcmPlaybackStream()
        stream.config(sourceRate)
        stream.push(pcm: pcm)
        _ = render(stream, count: 1000, deviceRate: deviceRate)
        stream.flush()
        let silenced = render(stream, count: 200, deviceRate: deviceRate)
        XCTAssertTrue(silenced.allSatisfy { $0 == 0 })

        stream.push(pcm: pcm)
        let fresh = PcmPlaybackStream()
        fresh.config(sourceRate)
        fresh.push(pcm: pcm)
        let length = Int((Double(pcm.count) * deviceRate / sourceRate).rounded(.up))
        sameSamples(render(stream, count: length, deviceRate: deviceRate), render(fresh, count: length, deviceRate: deviceRate))
    }

    func testOddByteWaitsForTheNextPacket() {
        var assembler = PcmFrameAssembler()
        XCTAssertEqual(assembler.push(Data([0x01, 0x00, 0x02])), [1])
        XCTAssertEqual(assembler.push(Data([0x00])), [2])
        XCTAssertNil(assembler.push(Data([0xFF])))
        XCTAssertEqual(assembler.push(Data([0x7F])), [32767])
        assembler.reset()
        XCTAssertNil(assembler.push(Data([0x00])))
    }

    func testOddByteSplitMatchesTheWholeSignal() {
        let pcm = Self.ramp(4000)
        var bytes = Data()
        for sample in pcm {
            var little = sample.littleEndian
            withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
        }
        let whole = PcmPlaybackStream()
        whole.config(sourceRate)
        whole.push(data: bytes)
        let split = PcmPlaybackStream()
        split.config(sourceRate)
        var offset = 0
        var toggle = true
        while offset < bytes.count {
            let size = toggle ? 1 : 17
            toggle.toggle()
            let end = min(bytes.count, offset + size)
            split.push(data: bytes.subdata(in: offset ..< end))
            offset = end
        }
        let length = Int((Double(pcm.count) * 48_000 / sourceRate).rounded(.up)) + Int((48_000 * 0.02).rounded(.up))
        sameSamples(render(whole, count: length, deviceRate: 48_000), render(split, count: length, deviceRate: 48_000))
    }

    private func play(_ chunks: [[Int16]], deviceRate: Double) -> [Float] {
        let stream = PcmPlaybackStream()
        stream.config(sourceRate)
        var total = 0
        for chunk in chunks {
            stream.push(pcm: chunk)
            total += chunk.count
        }
        let length = Int((Double(total) * deviceRate / sourceRate).rounded(.up)) + Int((deviceRate * 0.02).rounded(.up))
        return render(stream, count: length, deviceRate: deviceRate)
    }

    private func render(_ stream: PcmPlaybackStream, count: Int, deviceRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let block = 128
        var offset = 0
        while offset < out.count {
            let end = min(out.count, offset + block)
            out.withUnsafeMutableBufferPointer { buffer in
                _ = stream.render(into: buffer.baseAddress! + offset, count: end - offset, deviceRate: deviceRate)
            }
            offset = end
        }
        return out
    }

    private func sameSamples(_ left: [Float], _ right: [Float]) {
        XCTAssertEqual(left.count, right.count)
        for index in 0 ..< min(left.count, right.count) {
            if left[index] != right[index] {
                XCTFail("sample \(index): \(left[index]) != \(right[index])")
                return
            }
        }
    }

    private static func ramp(_ length: Int) -> [Int16] {
        (0 ..< length).map { index in
            Int16(1000 + (index % 50) * 300)
        }
    }

    private static func chunks(of pcm: [Int16], size: Int) -> [[Int16]] {
        var chunks: [[Int16]] = []
        var offset = 0
        while offset < pcm.count {
            let end = min(pcm.count, offset + size)
            chunks.append(Array(pcm[offset ..< end]))
            offset = end
        }
        return chunks
    }
}
