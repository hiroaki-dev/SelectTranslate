import Foundation

enum CodexSettings {
    private static let modelDefaultsKey = "codexModel"
    private static let loadsUserConfigDefaultsKey = "codexLoadsUserConfig"
    private static let configOverridesDefaultsKey = "codexConfigOverrides"

    static var model: String {
        get {
            normalizedStoredValue(forKey: modelDefaultsKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelDefaultsKey)
        }
    }

    /// When enabled, `codex exec` reads `~/.codex/config.toml` instead of running with `--ignore-user-config`.
    static var loadsUserConfig: Bool {
        get {
            UserDefaults.standard.bool(forKey: loadsUserConfigDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: loadsUserConfigDefaultsKey)
        }
    }

    /// One `key=value` per line, each passed to `codex exec` as `-c key=value`.
    static var configOverrides: String {
        get {
            UserDefaults.standard.string(forKey: configOverridesDefaultsKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: configOverridesDefaultsKey)
        }
    }

    private static func normalizedStoredValue(forKey key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
