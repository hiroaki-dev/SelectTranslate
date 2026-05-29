import Foundation

enum TranslationDirection {
    case englishToJapanese
    case japaneseToEnglish

    static func detect(_ text: String) -> TranslationDirection {
        let containsJapanese = text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF:
                return true
            default:
                return false
            }
        }

        return containsJapanese ? .japaneseToEnglish : .englishToJapanese
    }

    var label: String {
        switch self {
        case .englishToJapanese:
            return "English -> Japanese"
        case .japaneseToEnglish:
            return "Japanese -> English"
        }
    }

    var reversed: TranslationDirection {
        switch self {
        case .englishToJapanese:
            return .japaneseToEnglish
        case .japaneseToEnglish:
            return .englishToJapanese
        }
    }

    var promptInstruction: String {
        switch self {
        case .englishToJapanese:
            return "Translate the text from English to natural Japanese."
        case .japaneseToEnglish:
            return "Translate the text from Japanese to natural English."
        }
    }
}

enum TranslationServiceError: LocalizedError {
    case commandFailed(provider: TranslationProvider, commandName: String, status: Int32, output: String)
    case emptyResponse(provider: TranslationProvider)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(provider, commandName, status, output):
            let detail = Self.conciseError(from: output)
            let installHint = provider == .plamo
                ? " Install PLaMo support with: python3 -m pip install mlx-lm numba"
                : ""
            if detail.isEmpty {
                return "\(commandName) exited with status \(status).\(installHint)"
            }
            return "\(commandName) exited with status \(status): \(detail)\(installHint)"
        case let .emptyResponse(provider):
            return "\(provider.description) returned an empty translation."
        }
    }

    private static func conciseError(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let errorLine = lines.last(where: { $0.localizedCaseInsensitiveContains("ERROR:") }) {
            return String(errorLine.prefix(900))
        }

        return String(trimmed.prefix(1200))
    }
}

final class CodexTranslationService {
    private let workspaceURL: URL

    init(workspaceURL: URL = CodexTranslationService.defaultWorkspaceURL()) {
        self.workspaceURL = workspaceURL
    }

    func translate(
        _ text: String,
        direction: TranslationDirection,
        effort: ReasoningEffort,
        provider: TranslationProvider
    ) async throws -> String {
        switch provider {
        case .codex:
            return try await translateWithCodex(text, direction: direction, effort: effort)
        case .plamo:
            return try await translateWithPlamo(text)
        }
    }

    private func translateWithCodex(
        _ text: String,
        direction: TranslationDirection,
        effort: ReasoningEffort
    ) async throws -> String {
        let promptTemplate = PromptSettings.template
        return try await Task.detached(priority: .userInitiated) { [workspaceURL, effort, promptTemplate] in
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexTranslator-\(UUID().uuidString).txt")

            defer {
                try? FileManager.default.removeItem(at: outputURL)
            }

            let prompt = PromptSettings.render(template: promptTemplate, text: text, direction: direction)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = workspaceURL
            process.arguments = [
                "codex",
                "exec",
                "--ignore-user-config",
                "--skip-git-repo-check",
                "-c",
                "model_reasoning_effort=\"\(effort.rawValue)\"",
                "--cd",
                workspaceURL.path,
                "--output-last-message",
                outputURL.path,
                "-"
            ]
            process.environment = Self.processEnvironment(workspacePath: workspaceURL.path)

            let input = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = input
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            if let data = prompt.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            input.fileHandleForWriting.closeFile()

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            let combinedOutput = [stderrText, stdoutText]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            if process.terminationStatus != 0 {
                throw TranslationServiceError.commandFailed(
                    provider: .codex,
                    commandName: "codex exec",
                    status: process.terminationStatus,
                    output: combinedOutput
                )
            }

            let fileText = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            let translated = (fileText.isEmpty ? stdoutText : fileText)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if translated.localizedCaseInsensitiveContains("ERROR:") {
                throw TranslationServiceError.commandFailed(
                    provider: .codex,
                    commandName: "codex exec",
                    status: process.terminationStatus,
                    output: translated
                )
            }

            guard !translated.isEmpty else {
                throw TranslationServiceError.emptyResponse(provider: .codex)
            }

            return translated
        }.value
    }

    private func translateWithPlamo(_ text: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [workspaceURL] in
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = workspaceURL
            process.arguments = [
                "python3",
                "-m",
                "mlx_lm",
                "generate",
                "--model",
                "mlx-community/plamo-2-translate",
                "--extra-eos-token",
                "<|plamo:op|>",
                "--prompt",
                text
            ]
            process.environment = Self.processEnvironment(workspacePath: workspaceURL.path)

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            let combinedOutput = [stderrText, stdoutText]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            if process.terminationStatus != 0 {
                throw TranslationServiceError.commandFailed(
                    provider: .plamo,
                    commandName: "python3 -m mlx_lm generate",
                    status: process.terminationStatus,
                    output: combinedOutput
                )
            }

            let translated = Self.parsePlamoOutput(stdoutText, sourceText: text)
            if translated.localizedCaseInsensitiveContains("ERROR:") {
                throw TranslationServiceError.commandFailed(
                    provider: .plamo,
                    commandName: "python3 -m mlx_lm generate",
                    status: process.terminationStatus,
                    output: translated
                )
            }

            guard !translated.isEmpty else {
                throw TranslationServiceError.emptyResponse(provider: .plamo)
            }

            return translated
        }.value
    }

    private static func parsePlamoOutput(_ output: String, sourceText: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lines = trimmed.components(separatedBy: .newlines)
        var sawOpeningSeparator = false
        var captured: [String] = []

        for line in lines {
            let lineTrimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlamoSeparator(lineTrimmed) {
                if sawOpeningSeparator {
                    break
                }
                sawOpeningSeparator = true
                continue
            }

            if sawOpeningSeparator {
                captured.append(line)
            }
        }

        let separatedOutput = removeSourceEcho(cleanPlamoContentLines(captured), sourceText: sourceText)
        if !separatedOutput.isEmpty {
            return separatedOutput
        }

        return removeSourceEcho(cleanPlamoContentLines(lines), sourceText: sourceText)
    }

    private static func cleanPlamoContentLines(_ lines: [String]) -> String {
        lines
            .filter { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmedLine.isEmpty
                    && !isPlamoSeparator(trimmedLine)
                    && !isPlamoStatsLine(trimmedLine)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeSourceEcho(_ output: String, sourceText: String) -> String {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, trimmedOutput.hasPrefix(trimmedSource) else {
            return trimmedOutput
        }

        return String(trimmedOutput.dropFirst(trimmedSource.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlamoSeparator(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { $0 == "=" }
    }

    private static func isPlamoStatsLine(_ line: String) -> Bool {
        line.hasPrefix("Prompt:")
            || line.hasPrefix("Generation:")
            || line.hasPrefix("Peak memory:")
    }

    private static func defaultWorkspaceURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let workspaceURL = baseURL
            .appendingPathComponent("CodexTranslator", isDirectory: true)
            .appendingPathComponent("CodexWorkspace", isDirectory: true)

        try? FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        return workspaceURL
    }

    private static func processEnvironment(workspacePath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = "\(existingPath):\(fallbackPath)"
        } else {
            environment["PATH"] = fallbackPath
        }
        environment["PWD"] = workspacePath
        return environment
    }
}
