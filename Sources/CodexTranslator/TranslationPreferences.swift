import Foundation

extension Notification.Name {
    static let translationProviderDidChange = Notification.Name("CodexTranslatorTranslationProviderDidChange")
}

enum TranslationPreferences {
    private static let providerDefaultsKey = "translationProvider"

    static var translationProvider: TranslationProvider {
        get {
            let savedProvider = UserDefaults.standard.string(forKey: providerDefaultsKey)
            let provider = savedProvider.flatMap(TranslationProvider.init(rawValue:)) ?? .codex
            if provider == .plamo, !PlamoSetupService.isSetupComplete {
                UserDefaults.standard.set(TranslationProvider.codex.rawValue, forKey: providerDefaultsKey)
                return .codex
            }
            return provider
        }
        set {
            let provider = newValue == .plamo && !PlamoSetupService.isSetupComplete ? .codex : newValue
            guard provider != translationProvider else { return }
            UserDefaults.standard.set(provider.rawValue, forKey: providerDefaultsKey)
            NotificationCenter.default.post(name: .translationProviderDidChange, object: provider)
        }
    }
}
