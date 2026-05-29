import Foundation

extension Notification.Name {
    static let translationProviderDidChange = Notification.Name("CodexTranslatorTranslationProviderDidChange")
}

enum TranslationPreferences {
    private static let providerDefaultsKey = "translationProvider"

    static var translationProvider: TranslationProvider {
        get {
            let savedProvider = UserDefaults.standard.string(forKey: providerDefaultsKey)
            return savedProvider.flatMap(TranslationProvider.init(rawValue:)) ?? .codex
        }
        set {
            guard newValue != translationProvider else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: providerDefaultsKey)
            NotificationCenter.default.post(name: .translationProviderDidChange, object: newValue)
        }
    }
}
