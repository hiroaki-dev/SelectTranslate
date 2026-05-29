import Foundation

enum AppPaths {
    static var applicationSupportURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = baseURL.appendingPathComponent("CodexTranslator", isDirectory: true)
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

    static func processEnvironment(workingDirectory: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
}
