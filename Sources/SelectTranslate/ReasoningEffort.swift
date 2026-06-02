import Foundation

enum ReasoningEffort: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .xhigh:
            return "XHigh"
        }
    }
}
