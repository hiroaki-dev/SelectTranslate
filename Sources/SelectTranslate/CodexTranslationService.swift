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

typealias TranslationProgressHandler = @MainActor @Sendable (String) -> Void

final class CodexTranslationService {
    private static let minimumPlamoMaxTokens = 1024
    private static let maximumPlamoMaxTokens = 8192

    private let workspaceURL: URL

    init(workspaceURL: URL = CodexTranslationService.defaultWorkspaceURL()) {
        self.workspaceURL = workspaceURL
    }

    func translate(
        _ text: String,
        direction: TranslationDirection,
        effort: ReasoningEffort,
        provider: TranslationProvider,
        promptTemplate: String,
        onPartialResult: @escaping TranslationProgressHandler = { _ in }
    ) async throws -> String {
        switch provider {
        case .codex:
            return try await translateWithCodex(text, direction: direction, effort: effort, promptTemplate: promptTemplate)
        case .claude:
            return try await translateWithClaude(text, direction: direction, effort: effort, promptTemplate: promptTemplate)
        case .plamo:
            return try await translateWithPlamo(text, onPartialResult: onPartialResult)
        case .openAICompatible:
            return try await translateWithOpenAICompatibleAPI(
                text,
                direction: direction,
                promptTemplate: promptTemplate,
                onPartialResult: onPartialResult
            )
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

    private func translateWithClaude(
        _ text: String,
        direction: TranslationDirection,
        effort: ReasoningEffort,
        promptTemplate: String
    ) async throws -> String {
        let model = ClaudeSettings.model
        return try await Task.detached(priority: .userInitiated) { [workspaceURL, effort, model, promptTemplate] in
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

            let prompt = PromptSettings.render(template: promptTemplate, text: text, direction: direction)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = workspaceURL
            process.arguments = [
                "claude",
                "-p",
                "--safe-mode",
                "--no-session-persistence",
                "--output-format",
                "text"
            ]
            if !model.isEmpty {
                process.arguments?.append(contentsOf: ["--model", model])
            }
            process.arguments?.append(contentsOf: ["--effort", effort.rawValue])
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
                    provider: .claude,
                    commandName: "claude -p",
                    status: process.terminationStatus,
                    output: combinedOutput
                )
            }

            let translated = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            if translated.localizedCaseInsensitiveContains("ERROR:") {
                throw TranslationServiceError.commandFailed(
                    provider: .claude,
                    commandName: "claude -p",
                    status: process.terminationStatus,
                    output: translated
                )
            }

            guard !translated.isEmpty else {
                throw TranslationServiceError.emptyResponse(provider: .claude)
            }

            return translated
        }.value
    }

    private func translateWithPlamo(
        _ text: String,
        onPartialResult: @escaping TranslationProgressHandler
    ) async throws -> String {
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
                "--max-tokens",
                "\(Self.plamoMaxTokens(for: text))",
                "--prompt",
                text
            ]
            process.environment = Self.processEnvironment(workingDirectory: workspaceURL.path)

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let outputCollector = LockedProcessOutput()
            let partialState = LockedLatestText()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                let stdoutText = outputCollector.appendStdout(data)
                let partial = Self.parsePlamoOutput(stdoutText, sourceText: text)
                guard !partial.isEmpty else { return }

                if partialState.updateIfChanged(partial) {
                    Task {
                        await onPartialResult(partial)
                    }
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                outputCollector.appendStderr(data)
            }

            try process.run()

            process.waitUntilExit()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            outputCollector.appendStdout(stdout.fileHandleForReading.readDataToEndOfFile())
            outputCollector.appendStderr(stderr.fileHandleForReading.readDataToEndOfFile())

            let stdoutText = outputCollector.stdoutText
            let stderrText = outputCollector.stderrText
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

            await onPartialResult(translated)
            return translated
        }.value
    }

    private func translateWithOpenAICompatibleAPI(
        _ text: String,
        direction: TranslationDirection,
        promptTemplate: String,
        onPartialResult: @escaping TranslationProgressHandler
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
                ],
                stream: true
            )
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationServiceError.invalidResponse(
                provider: .openAICompatible,
                message: "Missing HTTP response."
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var responseText = ""
            for try await line in bytes.lines {
                responseText += line
                responseText += "\n"
            }
            throw TranslationServiceError.requestFailed(
                provider: .openAICompatible,
                status: httpResponse.statusCode,
                output: responseText
            )
        }

        var accumulatedText = ""
        for try await line in bytes.lines {
            guard let delta = try Self.parseOpenAIStreamLine(line) else {
                continue
            }

            accumulatedText += delta
            let partial = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty {
                await onPartialResult(partial)
            }
        }

        let translated = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else {
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

    private static func parseOpenAIStreamLine(_ line: String) throws -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.hasPrefix("data:") else {
            return nil
        }

        let payload = trimmedLine
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty, payload != "[DONE]" else {
            return nil
        }

        do {
            let response = try JSONDecoder().decode(
                OpenAIChatCompletionStreamResponse.self,
                from: Data(payload.utf8)
            )
            if let message = response.error?.message, !message.isEmpty {
                throw TranslationServiceError.invalidResponse(provider: .openAICompatible, message: message)
            }
            return response.choices?.compactMap { $0.delta?.content }.joined()
        } catch let error as TranslationServiceError {
            throw error
        } catch {
            throw TranslationServiceError.invalidResponse(
                provider: .openAICompatible,
                message: error.localizedDescription
            )
        }
    }

    private static func plamoMaxTokens(for text: String) -> Int {
        let nonWhitespaceScalarCount = text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }.count
        let estimatedTokenLimit = max(minimumPlamoMaxTokens, nonWhitespaceScalarCount * 2)
        return min(maximumPlamoMaxTokens, estimatedTokenLimit)
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

private final class LockedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    var stdoutText: String {
        lock.lock()
        defer { lock.unlock() }
        return stdoutBuffer
    }

    var stderrText: String {
        lock.lock()
        defer { lock.unlock() }
        return stderrBuffer
    }

    @discardableResult
    func appendStdout(_ data: Data) -> String {
        append(data, to: \.stdoutBuffer)
    }

    @discardableResult
    func appendStderr(_ data: Data) -> String {
        append(data, to: \.stderrBuffer)
    }

    private func append(_ data: Data, to keyPath: ReferenceWritableKeyPath<LockedProcessOutput, String>) -> String {
        let chunk = String(data: data, encoding: .utf8) ?? ""
        lock.lock()
        if !data.isEmpty {
            self[keyPath: keyPath] += chunk
        }
        let text = self[keyPath: keyPath]
        lock.unlock()
        return text
    }
}

private final class LockedLatestText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func updateIfChanged(_ newText: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard newText != text else {
            return false
        }

        text = newText
        return true
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
    let stream: Bool
}

private struct OpenAIChatCompletionStreamResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta?
    }

    let choices: [Choice]?
    let error: APIError?
}
