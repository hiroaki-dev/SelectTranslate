import Foundation

enum TranslationDirection: Hashable {
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

    var targetLanguage: String {
        switch self {
        case .englishToJapanese:
            return "Japanese"
        case .japaneseToEnglish:
            return "English"
        }
    }
}

enum TranslationServiceError: LocalizedError {
    case commandFailed(provider: TranslationProvider, commandName: String, status: Int32, output: String)
    case emptyResponse(provider: TranslationProvider)
    case invalidConfiguration(provider: TranslationProvider, message: String)
    case requestFailed(provider: TranslationProvider, status: Int, output: String)
    case invalidResponse(provider: TranslationProvider, message: String)
    case providerNotReady(provider: TranslationProvider, message: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(provider, commandName, status, output):
            let detail = Self.conciseError(from: output)
            let installHint = provider == .plamo
                ? " Run Prepare PLaMo in Settings before selecting the local model."
                : ""
            if detail.isEmpty {
                return "\(commandName) exited with status \(status).\(installHint)"
            }
            return "\(commandName) exited with status \(status): \(detail)\(installHint)"
        case let .emptyResponse(provider):
            return "\(provider.description) returned an empty translation."
        case let .invalidConfiguration(provider, message):
            return "\(provider.description) settings are incomplete: \(message)"
        case let .requestFailed(provider, status, output):
            let detail = Self.conciseError(from: output)
            if detail.isEmpty {
                return "\(provider.description) request failed with HTTP \(status)."
            }
            return "\(provider.description) request failed with HTTP \(status): \(detail)"
        case let .invalidResponse(provider, message):
            return "\(provider.description) returned an invalid response: \(message)"
        case let .providerNotReady(provider, message):
            return "\(provider.description) is not ready: \(message)"
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
        provider: TranslationProvider,
        promptTemplate: String
    ) async throws -> String {
        switch provider {
        case .codex:
            return try await translateWithCodex(text, direction: direction, effort: effort, promptTemplate: promptTemplate)
        case .plamo:
            return try await translateWithPlamo(text)
        case .openAICompatible:
            return try await translateWithOpenAICompatibleAPI(text, direction: direction, promptTemplate: promptTemplate)
        }
    }

    private func translateWithCodex(
        _ text: String,
        direction: TranslationDirection,
        effort: ReasoningEffort,
        promptTemplate: String
    ) async throws -> String {
        return try await Task.detached(priority: .userInitiated) { [workspaceURL, effort, promptTemplate] in
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SelectTranslate-\(UUID().uuidString).txt")

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
            process.environment = Self.processEnvironment(workingDirectory: workspaceURL.path)

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
            guard PlamoSetupService.isSetupComplete else {
                throw TranslationServiceError.providerNotReady(
                    provider: .plamo,
                    message: "Run Prepare PLaMo in Settings before selecting it."
                )
            }

            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = AppPaths.plamoPythonURL
            process.currentDirectoryURL = workspaceURL
            process.arguments = [
                "-m",
                "mlx_lm",
                "generate",
                "--model",
                PlamoSetupService.modelID,
                "--trust-remote-code",
                "--extra-eos-token",
                PlamoSetupService.extraEOSToken,
                "--prompt",
                text
            ]
            process.environment = Self.processEnvironment(workingDirectory: workspaceURL.path)

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

    private func translateWithOpenAICompatibleAPI(
        _ text: String,
        direction: TranslationDirection,
        promptTemplate: String
    ) async throws -> String {
        let configuration = OpenAICompatibleConfiguration.current()
        guard !configuration.baseURL.isEmpty else {
            throw TranslationServiceError.invalidConfiguration(
                provider: .openAICompatible,
                message: "Set base_url in Settings."
            )
        }
        guard !configuration.model.isEmpty else {
            throw TranslationServiceError.invalidConfiguration(
                provider: .openAICompatible,
                message: "Set model in Settings."
            )
        }
        guard configuration.includesV1Path else {
            throw TranslationServiceError.invalidConfiguration(
                provider: .openAICompatible,
                message: "base_url must include /v1."
            )
        }
        guard let endpointURL = configuration.chatCompletionsURL else {
            throw TranslationServiceError.invalidConfiguration(
                provider: .openAICompatible,
                message: "base_url must be a valid URL including /v1."
            )
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatCompletionRequest(
                model: configuration.model,
                messages: [
                    .init(
                        role: "system",
                        content: "You are a precise translation engine. Return only the translated text. Do not add explanations, alternatives, labels, quotes, or notes."
                    ),
                    .init(
                        role: "user",
                        content: PromptSettings.render(
                            template: promptTemplate,
                            text: text,
                            direction: direction
                        )
                    )
                ]
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationServiceError.invalidResponse(
                provider: .openAICompatible,
                message: "Missing HTTP response."
            )
        }

        let responseText = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationServiceError.requestFailed(
                provider: .openAICompatible,
                status: httpResponse.statusCode,
                output: responseText
            )
        }

        let decodedResponse: OpenAIChatCompletionResponse
        do {
            decodedResponse = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            throw TranslationServiceError.invalidResponse(
                provider: .openAICompatible,
                message: error.localizedDescription
            )
        }

        guard let translated = decodedResponse.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !translated.isEmpty else {
            throw TranslationServiceError.emptyResponse(provider: .openAICompatible)
        }

        return translated
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
        AppPaths.codexWorkspaceURL
    }

    private static func processEnvironment(workingDirectory: String) -> [String: String] {
        AppPaths.processEnvironment(workingDirectory: workingDirectory)
    }
}

private struct OpenAICompatibleConfiguration {
    let baseURL: String
    let apiKey: String
    let model: String

    var normalizedBaseURL: String {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBaseURL.hasSuffix("/")
            ? String(trimmedBaseURL.dropLast())
            : trimmedBaseURL
    }

    var includesV1Path: Bool {
        guard let url = URL(string: normalizedBaseURL) else {
            return false
        }

        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("v1")
    }

    var chatCompletionsURL: URL? {
        return URL(string: "\(normalizedBaseURL)/chat/completions")
    }

    static func current() -> OpenAICompatibleConfiguration {
        OpenAICompatibleConfiguration(
            baseURL: OpenAICompatibleSettings.baseURL,
            apiKey: OpenAICompatibleSettings.apiKey,
            model: OpenAICompatibleSettings.model
        )
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}
