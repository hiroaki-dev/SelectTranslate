import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable, Hashable {
    case codex
    case plamo
    case openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex:
            return "Codex"
        case .plamo:
            return "PLaMo"
        case .openAICompatible:
            return "API"
        }
    }

    var description: String {
        switch self {
        case .codex:
            return "codex exec"
        case .plamo:
            return "PLaMo MLX"
        case .openAICompatible:
            return "OpenAI-compatible API"
        }
    }
}
