import AppIntents

@available(iOS 16.0, *)
struct OpenSynaplanIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Synaplan"
    static var description: IntentDescription = "Opens the Synaplan app."
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        ShortcutActionStore.shared.set(.open)
        return .result()
    }
}

@available(iOS 16.0, *)
struct StartDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start dictation"
    static var description: IntentDescription = "Opens Synaplan and starts voice dictation in the chat."
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        ShortcutActionStore.shared.set(.dictate)
        return .result()
    }
}

@available(iOS 16.0, *)
struct AnalyzePhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Analyze photo"
    static var description: IntentDescription = "Opens Synaplan and the camera so a photo can be attached to the chat."
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        ShortcutActionStore.shared.set(.analyzePhoto)
        return .result()
    }
}
