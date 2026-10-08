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

    func testLevelOfSilenceAndFullScale() {
        let silence = [Float](repeating: 0, count: 64)
        let full = [Float](repeating: 1, count: 64)
        XCTAssertEqual(silence.withUnsafeBufferPointer { UtteranceEndpointer.levelDb(samples: $0.baseAddress!, count: 64) }, -160)
        XCTAssertEqual(full.withUnsafeBufferPointer { UtteranceEndpointer.levelDb(samples: $0.baseAddress!, count: 64) }, 0, accuracy: 0.001)
    }
}
