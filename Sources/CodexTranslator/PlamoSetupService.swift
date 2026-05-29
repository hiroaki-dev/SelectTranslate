import Foundation

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
    static let modelID = "mlx-community/plamo-2-translate"
    static let extraEOSToken = "<|plamo:op|>"

    private static var setupMarkerURL: URL {
        AppPaths.applicationSupportURL.appendingPathComponent("PLaMoSetupComplete")
    }

    static var isSetupComplete: Bool {
        FileManager.default.fileExists(atPath: setupMarkerURL.path)
            && FileManager.default.isExecutableFile(atPath: AppPaths.plamoPythonURL.path)
    }

    static func prepare(progress: @escaping @Sendable (String) -> Void) async throws {
        try await PlamoSetupCoordinator.shared.prepare(progress: progress)
    }

    fileprivate static func performSetup(progress: @escaping @Sendable (String) -> Void) throws {
        try? FileManager.default.removeItem(at: setupMarkerURL)
        try FileManager.default.createDirectory(at: AppPaths.applicationSupportURL, withIntermediateDirectories: true)

        if !FileManager.default.isExecutableFile(atPath: AppPaths.plamoPythonURL.path) {
            progress("Creating local Python environment.")
            try run(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", "-m", "venv", AppPaths.plamoEnvironmentURL.path],
                commandName: "python3 -m venv"
            )
        }

        progress("Installing MLX dependencies.")
        try run(
            executable: AppPaths.plamoPythonURL,
            arguments: ["-m", "pip", "install", "-U", "mlx-lm", "numba"],
            commandName: "python3 -m pip install"
        )

        progress("Downloading PLaMo model.")
        try run(
            executable: AppPaths.plamoPythonURL,
            arguments: [
                "-m",
                "mlx_lm",
                "generate",
                "--model",
                modelID,
                "--extra-eos-token",
                extraEOSToken,
                "--prompt",
                "こんにちは"
            ],
            commandName: "python3 -m mlx_lm generate"
        )

        try "ready\n".write(to: setupMarkerURL, atomically: true, encoding: .utf8)
        progress("PLaMo is ready.")
    }

    private static func run(executable: URL, arguments: [String], commandName: String) throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTranslator-PLaMoSetup-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = AppPaths.applicationSupportURL
        process.environment = AppPaths.processEnvironment(workingDirectory: AppPaths.applicationSupportURL.path)
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        try process.run()
        process.waitUntilExit()
        try? outputHandle.synchronize()

        guard process.terminationStatus == 0 else {
            let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            throw PlamoSetupError.commandFailed(
                command: commandName,
                status: process.terminationStatus,
                output: output
            )
        }
    }
}

private actor PlamoSetupCoordinator {
    static let shared = PlamoSetupCoordinator()

    private var currentTask: Task<Void, Error>?

    func prepare(progress: @escaping @Sendable (String) -> Void) async throws {
        if PlamoSetupService.isSetupComplete {
            progress("PLaMo is ready.")
            return
        }

        if let currentTask {
            try await currentTask.value
            progress("PLaMo is ready.")
            return
        }

        let task = Task.detached(priority: .userInitiated) {
            try PlamoSetupService.performSetup(progress: progress)
        }
        currentTask = task

        do {
            try await task.value
            currentTask = nil
        } catch {
            currentTask = nil
            throw error
        }
    }
}
