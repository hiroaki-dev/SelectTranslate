import Foundation

enum ClaudeSettings {
    private static let modelDefaultsKey = "claudeModel"

    static var model: String {
        get {
            normalizedStoredValue(forKey: modelDefaultsKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelDefaultsKey)
        }
    }

    private static func normalizedStoredValue(forKey key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
