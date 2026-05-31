import Foundation

enum OpenAICompatibleSettings {
    static let defaultBaseURL = "http://localhost:1234/v1"
    static let defaultAPIKey = "dummy"
    static let ollamaBaseURL = "http://localhost:11434/v1"
    static let ollamaAPIKey = "ollama"

    private static let baseURLDefaultsKey = "openAICompatibleBaseURL"
    private static let apiKeyDefaultsKey = "openAICompatibleAPIKey"
    private static let modelDefaultsKey = "openAICompatibleModel"

    static var baseURL: String {
        get {
            normalizedStoredValue(forKey: baseURLDefaultsKey) ?? defaultBaseURL
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLDefaultsKey)
        }
    }

    static var apiKey: String {
        get {
            normalizedStoredValue(forKey: apiKeyDefaultsKey) ?? defaultAPIKey
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiKeyDefaultsKey)
        }
    }

    static var model: String {
        get {
            normalizedStoredValue(forKey: modelDefaultsKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelDefaultsKey)
        }
    }

    static func useLMStudioDefaults() {
        baseURL = defaultBaseURL
        apiKey = defaultAPIKey
    }

    static func useOllamaDefaults() {
        baseURL = ollamaBaseURL
        apiKey = ollamaAPIKey
    }

    private static func normalizedStoredValue(forKey key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
