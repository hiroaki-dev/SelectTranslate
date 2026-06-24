import Foundation

enum PromptSettings {
    static let instructionToken = "{{instruction}}"
    static let textToken = "{{text}}"
    static let replyOriginalToken = "{{original}}"
    static let replyTranslationToken = "{{translation}}"
    static let replyDraftToken = "{{reply}}"
    static let replyTargetLanguageToken = "{{target_language}}"
    static let replySourceLanguageToken = "{{source_language}}"

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

    static let defaultReplyTemplate = """
    You are a precise translation engine.

    Translate the reply draft into natural {{target_language}}, using the original message and the existing translation as context.

    Rules:
    - Return only the translated reply.
    - Do not add explanations, alternatives, markdown fences, labels, quotes, or notes.
    - Preserve paragraph breaks, list structure, URLs, code identifiers, and placeholders where possible.
    - Keep the tone appropriate for the original message and the reply draft.

    Original {{source_language}} text:
    {{original}}

    Existing translation:
    {{translation}}

    Reply draft:
    {{reply}}
    """

    private static let templateDefaultsKey = "promptTemplate"
    private static let replyTemplateDefaultsKey = "replyPromptTemplate"
    private static let shortcutProfilesDefaultsKey = "shortcutProfiles"

    static var template: String {
        get {
            defaultShortcutProfile.promptTemplate
        }
        set {
            var profiles = shortcutProfiles
            if profiles.isEmpty {
                profiles = [ShortcutProfile.defaultProfile(promptTemplate: newValue)]
            } else {
                profiles[0].promptTemplate = newValue
            }
            saveShortcutProfiles(profiles)
        }
    }

    static var shortcutProfiles: [ShortcutProfile] {
        loadShortcutProfiles()
    }

    static var replyTemplate: String {
        get {
            let savedTemplate = UserDefaults.standard.string(forKey: replyTemplateDefaultsKey) ?? ""
            return savedTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? defaultReplyTemplate
                : savedTemplate
        }
        set {
            UserDefaults.standard.set(newValue, forKey: replyTemplateDefaultsKey)
        }
    }

    static var defaultShortcutProfile: ShortcutProfile {
        shortcutProfiles.first ?? ShortcutProfile.defaultProfile(promptTemplate: legacyTemplate)
    }

    static func profile(withID id: String) -> ShortcutProfile? {
        shortcutProfiles.first { $0.id == id }
    }

    static func saveShortcutProfiles(_ profiles: [ShortcutProfile]) {
        let normalizedProfiles = normalizeProfiles(profiles)
        if let data = try? JSONEncoder().encode(normalizedProfiles) {
            UserDefaults.standard.set(data, forKey: shortcutProfilesDefaultsKey)
            NotificationCenter.default.post(name: .shortcutProfilesDidChange, object: normalizedProfiles)
        }
    }

    static func resetTemplate() {
        resetTemplate(forProfileID: defaultShortcutProfile.id)
    }

    static func resetTemplate(forProfileID profileID: String) {
        var profiles = shortcutProfiles
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].promptTemplate = defaultTemplate
        saveShortcutProfiles(profiles)
    }

    static func resetReplyTemplate() {
        replyTemplate = defaultReplyTemplate
    }

    static func validationMessages(for profiles: [ShortcutProfile]) -> [String] {
        let normalizedProfiles = normalizeProfiles(profiles)
        guard !normalizedProfiles.isEmpty else {
            return ["At least one shortcut is required."]
        }

        var messages: [String] = []
        var shortcutsByKey: [String: [String]] = [:]

        for (originalProfile, profile) in zip(profiles, normalizedProfiles) {
            if originalProfile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append("Shortcut name cannot be empty.")
            }
            if profile.shortcut.normalizedModifiers == 0 {
                messages.append("\(profile.displayName) needs at least one modifier.")
            }
            if KeyboardShortcut.label(for: profile.keyCode) == nil {
                messages.append("\(profile.displayName) has an unsupported key.")
            }
            shortcutsByKey[profile.shortcut.storageKey, default: []].append(profile.displayName)
        }

        for names in shortcutsByKey.values where names.count > 1 {
            messages.append("Duplicate shortcut: \(names.joined(separator: ", ")).")
        }

        return Array(Set(messages)).sorted()
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

    static func renderReply(
        template: String,
        originalText: String,
        translatedText: String,
        replyDraft: String,
        direction: TranslationDirection
    ) -> String {
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultReplyTemplate
            : template
        var prompt = trimmedTemplate
            .replacingOccurrences(of: replyOriginalToken, with: originalText)
            .replacingOccurrences(of: replyTranslationToken, with: translatedText)
            .replacingOccurrences(of: replyDraftToken, with: replyDraft)
            .replacingOccurrences(of: replyTargetLanguageToken, with: direction.sourceLanguage)
            .replacingOccurrences(of: replySourceLanguageToken, with: direction.sourceLanguage)

        if !prompt.contains(replyDraft) {
            prompt += "\n\nReply draft:\n\(replyDraft)"
        }

        if !prompt.contains(originalText) {
            prompt += "\n\nOriginal \(direction.sourceLanguage) text:\n\(originalText)"
        }

        if !prompt.contains(translatedText) {
            prompt += "\n\nExisting \(direction.targetLanguage) translation:\n\(translatedText)"
        }

        return prompt
    }

    private static var legacyTemplate: String {
        let savedTemplate = UserDefaults.standard.string(forKey: templateDefaultsKey) ?? ""
        return savedTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTemplate : savedTemplate
    }

    private static func loadShortcutProfiles() -> [ShortcutProfile] {
        guard let data = UserDefaults.standard.data(forKey: shortcutProfilesDefaultsKey),
              let decodedProfiles = try? JSONDecoder().decode([ShortcutProfile].self, from: data) else {
            return [ShortcutProfile.defaultProfile(promptTemplate: legacyTemplate)]
        }

        let normalizedProfiles = normalizeProfiles(decodedProfiles)
        return normalizedProfiles.isEmpty
            ? [ShortcutProfile.defaultProfile(promptTemplate: legacyTemplate)]
            : normalizedProfiles
    }

    private static func normalizeProfiles(_ profiles: [ShortcutProfile]) -> [ShortcutProfile] {
        profiles.enumerated().map { index, profile in
            var normalized = profile
            if normalized.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                normalized.id = index == 0 ? "default" : UUID().uuidString
            }
            if normalized.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                normalized.name = "Untitled Shortcut"
            }
            normalized.modifiers = normalized.modifiers & KeyboardShortcutModifier.allMask
            if KeyboardShortcut.label(for: normalized.keyCode) == nil {
                normalized.keyCode = KeyboardShortcut.defaultKeyCode
            }
            if normalized.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                normalized.promptTemplate = defaultTemplate
            }
            return normalized
        }
    }
}
