import Foundation

/// CarPlay copy from `CarPlay.xcstrings`, resolved in the language the user
/// picked inside Synaplan (the same one used for recognition and replies), not
/// only the system language.
enum CarPlayStrings {
    static func text(_ key: String, language: String = CarSessionStore.shared.language) -> String {
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        let value = bundle.localizedString(forKey: key, value: nil, table: "CarPlay")
        if value != key { return value }
        return Bundle.main.localizedString(forKey: key, value: key, table: "CarPlay")
    }

    static func relativeTime(_ date: Date, language: String = CarSessionStore.shared.language) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
