import Foundation

extension Notification.Name {
    static let plamoSetupStatusDidChange = Notification.Name("SelectTranslatePlamoSetupStatusDidChange")
}

enum PlamoSetupError: LocalizedError {
    case commandFailed(command: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(command) exited with status \(status)."
            }
            return "\(command) exited with status \(status): \(String(detail.prefix(1200)))"
        }
    }
}

enum PlamoSetupService {
    private static let pythonPackages = ["mlx-lm", "mlx", "transformers", "numba"]
    private static let legacyModelRepositoryID = "mlx-community/plamo-2-translate"

    private static var environmentMarkerURL: URL {
        AppPaths.applicationSupportURL.appendingPathComponent("PLaMo3EnvironmentReady")
    }

    /// Written by PLaMo 2 setups. PLaMo 3 does not use it.
    private static var legacySetupMarkerURL: URL {
        AppPaths.applicationSupportURL.appendingPathComponent("PLaMoSetupComplete")
    }

    private static var modelMarkersURL: URL {
        AppPaths.applicationSupportURL.appendingPathComponent("PLaMo3Models", isDirectory: true)
    }

    private static func modelMarkerURL(for size: PlamoModelSize) -> URL {
        modelMarkersURL.appendingPathComponent("\(size.rawValue).ready")
    }

    private static func modelCacheURL(repositoryID: String) -> URL {
        AppPaths.huggingFaceCacheURL
            .appendingPathComponent("hub", isDirectory: true)
            .appendingPathComponent("models--\(repositoryID.replacingOccurrences(of: "/", with: "--"))", isDirectory: true)
    }

    static var isEnvironmentReady: Bool {
        FileManager.default.fileExists(atPath: environmentMarkerURL.path)
            && FileManager.default.isExecutableFile(atPath: AppPaths.plamoPythonURL.path)
    }

    /// True when PLaMo can translate, that is, when the environment and at least one model are installed.
    static var isSetupComplete: Bool {
        isEnvironmentReady && !installedModelSizes.isEmpty
    }

    static var installedModelSizes: Set<PlamoModelSize> {
        Set(PlamoModelSize.allCases.filter(isModelInstalled))
    }

    static func isModelInstalled(_ size: PlamoModelSize) -> Bool {
        FileManager.default.fileExists(atPath: modelMarkerURL(for: size).path)
            && modelSnapshotURL(for: size) != nil
    }

    /// The local snapshot directory of a downloaded model, passed to mlx-lm so that translation does not hit the network.
    static func modelSnapshotURL(for size: PlamoModelSize) -> URL? {
        let cacheURL = modelCacheURL(repositoryID: size.repositoryID)
        let refURL = cacheURL
            .appendingPathComponent("refs", isDirectory: true)
            .appendingPathComponent("main")
        guard let revision = try? String(contentsOf: refURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !revision.isEmpty else {
            return nil
        }

        let snapshotURL = cacheURL
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
        let configURL = snapshotURL.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configURL.path) ? snapshotURL : nil
    }

    static var hasLegacyModelCache: Bool {
        FileManager.default.fileExists(atPath: modelCacheURL(repositoryID: legacyModelRepositoryID).path)
    }

    /// Prepares the shared Python environment if needed and downloads one model size.
    static func download(_ size: PlamoModelSize, progress: @escaping @Sendable (String) -> Void) async throws {
        try await PlamoSetupCoordinator.shared.run {
            try performDownload(size, progress: progress)
        }
    }

    static func delete(_ size: PlamoModelSize) async throws {
        try await PlamoSetupCoordinator.shared.run {
            try? FileManager.default.removeItem(at: modelMarkerURL(for: size))
            try removeItemIfPresent(at: modelCacheURL(repositoryID: size.repositoryID))
            postStatusChange()
        }
    }

    static func deleteLegacyModelCache() async throws {
        try await PlamoSetupCoordinator.shared.run {
            try removeItemIfPresent(at: modelCacheURL(repositoryID: legacyModelRepositoryID))
            try? FileManager.default.removeItem(at: legacySetupMarkerURL)
            postStatusChange()
        }
    }

    fileprivate static func performDownload(
        _ size: PlamoModelSize,
        progress: @escaping @Sendable (String) -> Void
    ) throws {
        if !isEnvironmentReady {
            try prepareEnvironment(progress: progress)
        }

        if isModelInstalled(size) {
            progress("PLaMo 3 \(size.label) is already installed.")
            return
        }

        try? FileManager.default.removeItem(at: modelMarkerURL(for: size))
        try FileManager.default.createDirectory(at: modelMarkersURL, withIntermediateDirectories: true)

        progress("Downloading PLaMo 3 \(size.label) (about \(size.approximateDownloadSize)).")
        try run(
            executable: AppPaths.plamoPythonURL,
            arguments: [
                "-c",
                "import sys; from huggingface_hub import snapshot_download; print(snapshot_download(sys.argv[1]))",
                size.repositoryID
            ],
            commandName: "snapshot_download \(size.repositoryID)",
            progress: progress
        )

        try "\(size.repositoryID)\n".write(to: modelMarkerURL(for: size), atomically: true, encoding: .utf8)
        guard isModelInstalled(size) else {
            try? FileManager.default.removeItem(at: modelMarkerURL(for: size))
            throw PlamoSetupError.commandFailed(
                command: "snapshot_download \(size.repositoryID)",
                status: 0,
                output: "The downloaded model files were not found in the Hugging Face cache."
            )
        }

        postStatusChange()
        progress("PLaMo 3 \(size.label) is ready.")
    }

    private static func prepareEnvironment(progress: @escaping @Sendable (String) -> Void) throws {
        try? FileManager.default.removeItem(at: environmentMarkerURL)
        try? FileManager.default.removeItem(at: legacySetupMarkerURL)
        try FileManager.default.createDirectory(at: AppPaths.applicationSupportURL, withIntermediateDirectories: true)

        if !FileManager.default.isExecutableFile(atPath: AppPaths.plamoPythonURL.path) {
            progress("Creating local Python environment.")
            try run(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", "-m", "venv", AppPaths.plamoEnvironmentURL.path],
                commandName: "python3 -m venv",
                progress: progress
            )
        } else {
            progress("Using existing local Python environment.")
        }

        progress("Installing PLaMo dependencies.")
        try run(
            executable: AppPaths.plamoPythonURL,
            arguments: ["-m", "pip", "install", "-U"] + pythonPackages,
            commandName: "python3 -m pip install",
            progress: progress
        )

        try "ready\n".write(to: environmentMarkerURL, atomically: true, encoding: .utf8)
    }

    private static func removeItemIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func postStatusChange() {
        NotificationCenter.default.post(name: .plamoSetupStatusDidChange, object: nil)
    }

    private static func run(
        executable: URL,
        arguments: [String],
        commandName: String,
        progress: @escaping @Sendable (String) -> Void
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = AppPaths.applicationSupportURL
        process.environment = AppPaths.processEnvironment(workingDirectory: AppPaths.applicationSupportURL.path)

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        progress("$ \(commandName)")
        try process.run()

        var combinedOutput = ""
        while true {
            let data = outputPipe.fileHandleForReading.availableData
            if data.isEmpty {
                break
            }

            let chunk = String(data: data, encoding: .utf8) ?? ""
            combinedOutput += chunk
            for line in progressLines(from: chunk) {
                progress(line)
            }
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PlamoSetupError.commandFailed(
                command: commandName,
                status: process.terminationStatus,
                output: combinedOutput
            )
        }
    }

    private static func progressLines(from chunk: String) -> [String] {
        chunk
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map(cleanProgressLine)
            .filter { !$0.isEmpty }
    }

    private static func cleanProgressLine(_ line: String) -> String {
        let withoutANSI = line.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        let trimmed = withoutANSI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 260 else {
            return trimmed
        }
        return "\(trimmed.prefix(257))..."
    }
}

/// Runs PLaMo setup operations one at a time so that downloads and deletions never overlap.
private actor PlamoSetupCoordinator {
    static let shared = PlamoSetupCoordinator()

    private var previousTask: Task<Void, Error>?

    func run(_ operation: @escaping @Sendable () throws -> Void) async throws {
        let previousTask = previousTask
        let task = Task.detached(priority: .userInitiated) {
            _ = try? await previousTask?.value
            try operation()
        }
        self.previousTask = task
        try await task.value
    }
}
