import Foundation

enum PromptSettings {
    static let instructionToken = "{{instruction}}"
    static let textToken = "{{text}}"

    static let defaultTemplate = """
    You are a precise translation engine.

    {{instruction}}

    Rules:
    - Return only the translated text.
    - Do not add explanations, alternatives, markdown fences, labels, quotes, or notes.
    - Preserve paragraph breaks, list structure, URLs, code identifiers, and placeholders where possible.
    - If the source text contains a mixture of languages, translate only the main natural-language content.

    Source text:
    {{text}}
    """

    private static let templateDefaultsKey = "promptTemplate"

    static var template: String {
        get {
            let savedTemplate = UserDefaults.standard.string(forKey: templateDefaultsKey) ?? ""
            return savedTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTemplate : savedTemplate
        }
        set {
            UserDefaults.standard.set(newValue, forKey: templateDefaultsKey)
        }
    }

    static func resetTemplate() {
        UserDefaults.standard.removeObject(forKey: templateDefaultsKey)
    }

    static func render(template: String, text: String, direction: TranslationDirection) -> String {
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTemplate : template
        var prompt = trimmedTemplate
            .replacingOccurrences(of: instructionToken, with: direction.promptInstruction)
            .replacingOccurrences(of: textToken, with: text)

        if !prompt.contains(direction.promptInstruction) {
            prompt += "\n\n\(direction.promptInstruction)"
        }

        if !prompt.contains(text) {
            prompt += "\n\nSource text:\n\(text)"
        }

        return prompt
    }
}
