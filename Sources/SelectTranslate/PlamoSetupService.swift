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
                commandName: "python3 -m venv",
                progress: progress
            )
        } else {
            progress("Using existing local Python environment.")
        }

        progress("Installing PLaMo dependencies.")
        try run(
            executable: AppPaths.plamoPythonURL,
            arguments: ["-m", "pip", "install", "-U", "mlx-lm", "numba", "torch"],
            commandName: "python3 -m pip install",
            progress: progress
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
                "--trust-remote-code",
                "--extra-eos-token",
                extraEOSToken,
                "--prompt",
                "こんにちは"
            ],
            commandName: "python3 -m mlx_lm generate",
            progress: progress
        )

        try "ready\n".write(to: setupMarkerURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .plamoSetupStatusDidChange, object: nil)
        progress("PLaMo is ready.")
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
