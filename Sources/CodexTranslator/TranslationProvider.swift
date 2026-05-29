import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable {
    case codex
    case plamo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex:
            return "Codex"
        case .plamo:
            return "PLaMo"
        }
    }

    var description: String {
        switch self {
        case .codex:
            return "codex exec"
        case .plamo:
            return "PLaMo MLX"
        }
    }
}
