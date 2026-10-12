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
}
