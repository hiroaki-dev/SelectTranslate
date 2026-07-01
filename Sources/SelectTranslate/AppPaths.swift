import Foundation

enum AppPaths {
    private static let applicationSupportDirectoryName = "SelectTranslate"
    private static let legacyApplicationSupportDirectoryName = "CodexTranslator"

    static var applicationSupportURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = baseURL.appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
        migrateLegacyApplicationSupportIfNeeded(from: baseURL, to: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var codexWorkspaceURL: URL {
        let url = applicationSupportURL.appendingPathComponent("CodexWorkspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var plamoEnvironmentURL: URL {
        applicationSupportURL.appendingPathComponent("PLaMoEnvironment", isDirectory: true)
    }

    static var plamoPythonURL: URL {
        plamoEnvironmentURL
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
    }

    static var huggingFaceCacheURL: URL {
        let url = applicationSupportURL.appendingPathComponent("HuggingFace", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var translationHistoryDatabaseURL: URL {
        applicationSupportURL.appendingPathComponent("TranslationHistory.sqlite3")
    }

    static var learningTermsDatabaseURL: URL {
        applicationSupportURL.appendingPathComponent("LearningTerms.sqlite3")
    }

    static func processEnvironment(workingDirectory: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let homeLocalBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .path
        let fallbackPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            homeLocalBin,
            "/Applications/cmux.app/Contents/Resources/bin"
        ].joined(separator: ":")
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = "\(existingPath):\(fallbackPath)"
        } else {
            environment["PATH"] = fallbackPath
        }
        environment["PWD"] = workingDirectory
        environment["HF_HOME"] = huggingFaceCacheURL.path
        environment["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
        return environment
    }

    private static func migrateLegacyApplicationSupportIfNeeded(from baseURL: URL, to newURL: URL) {
        let legacyURL = baseURL.appendingPathComponent(legacyApplicationSupportDirectoryName, isDirectory: true)
        let fileManager = FileManager.default

        guard !fileManager.fileExists(atPath: newURL.path),
              fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        try? fileManager.moveItem(at: legacyURL, to: newURL)
    }
}
