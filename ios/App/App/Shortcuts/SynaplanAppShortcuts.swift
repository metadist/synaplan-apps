import AppIntents

@available(iOS 16.0, *)
struct SynaplanAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSynaplanIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Open Synaplan",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Dictate with \(.applicationName)",
                "Start dictation in \(.applicationName)",
            ],
            shortTitle: "Start dictation",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: AnalyzePhotoIntent(),
            phrases: [
                "Analyze a photo with \(.applicationName)",
                "Take a photo with \(.applicationName)",
            ],
            shortTitle: "Analyze photo",
            systemImageName: "camera"
        )
    }
}
