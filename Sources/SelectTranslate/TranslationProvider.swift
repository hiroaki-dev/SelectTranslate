import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable, Hashable {
    case codex
    case claude
    case plamo
    case foundationModels
    case openAICompatible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .plamo:
            return "PLaMo"
        case .foundationModels:
            // "Foundation Models" does not fit in a panel segment.
            return "Apple"
        case .openAICompatible:
            return "API"
        }
    }

    var description: String {
        switch self {
        case .codex:
            return "codex exec"
        case .claude:
            return "claude -p"
        case .plamo:
            return "PLaMo MLX"
        case .foundationModels:
            return "Apple Foundation Models"
        case .openAICompatible:
            return "OpenAI-compatible API"
        }
    }
}
