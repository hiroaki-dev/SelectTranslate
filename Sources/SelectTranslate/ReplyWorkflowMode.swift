enum ReplyWorkflowMode: String {
    case translation
    case correction

    var resultTitle: String {
        switch self {
        case .translation:
            return "Translated reply"
        case .correction:
            return "Correction result"
        }
    }

    var historySuffix: String {
        switch self {
        case .translation:
            return ""
        case .correction:
            return " · Correction"
        }
    }
}
