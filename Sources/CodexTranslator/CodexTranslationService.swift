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

    var promptInstruction: String {
        switch self {
        case .englishToJapanese:
            return "Translate the text from English to natural Japanese."
        case .japaneseToEnglish:
            return "Translate the text from Japanese to natural English."
        }
    }
}

enum CodexTranslationError: LocalizedError {
    case codexCommandFailed(status: Int32, stderr: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case let .codexCommandFailed(status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "codex exec exited with status \(status)."
            }
            return "codex exec exited with status \(status): \(detail)"
        case .emptyResponse:
            return "codex exec returned an empty translation."
        }
    }
}

final class CodexTranslationService {
    private let workspacePath: String

    init(workspacePath: String = FileManager.default.currentDirectoryPath) {
        self.workspacePath = workspacePath
    }

    func translate(_ text: String, direction: TranslationDirection, effort: ReasoningEffort) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [workspacePath, effort] in
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexTranslator-\(UUID().uuidString).txt")

            defer {
                try? FileManager.default.removeItem(at: outputURL)
            }

            let prompt = Self.makePrompt(text: text, direction: direction)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "codex",
                "exec",
                "--skip-git-repo-check",
                "-c",
                "model_reasoning_effort=\"\(effort.rawValue)\"",
                "--cd",
                workspacePath,
                "--output-last-message",
                outputURL.path,
                "-"
            ]
            process.environment = Self.processEnvironment()

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

            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                throw CodexTranslationError.codexCommandFailed(
                    status: process.terminationStatus,
                    stderr: stderrText
                )
            }

            let fileText = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
            let translated = (fileText.isEmpty ? stdoutText : fileText)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !translated.isEmpty else {
                throw CodexTranslationError.emptyResponse
            }

            return translated
        }.value
    }

    private static func makePrompt(text: String, direction: TranslationDirection) -> String {
        """
        You are a precise translation engine.

        \(direction.promptInstruction)

        Rules:
        - Return only the translated text.
        - Do not add explanations, alternatives, markdown fences, labels, quotes, or notes.
        - Preserve paragraph breaks, list structure, URLs, code identifiers, and placeholders where possible.
        - If the source text contains a mixture of languages, translate only the main natural-language content.

        Source text:
        \(text)
        """
    }

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = "\(existingPath):\(fallbackPath)"
        } else {
            environment["PATH"] = fallbackPath
        }
        return environment
    }
}
