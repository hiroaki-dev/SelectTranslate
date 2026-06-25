import Foundation

enum PromptSettings {
    static let instructionToken = "{{instruction}}"
    static let textToken = "{{text}}"
    static let replyOriginalToken = "{{original}}"
    static let replyTranslationToken = "{{translation}}"
    static let replyDraftToken = "{{reply}}"
    static let replyIntendedToken = "{{intended}}"
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

    Translate only the reply draft into natural {{target_language}}.
    Use the original message and existing translation only as context for meaning, references, tone, and terminology.

    Rules:
    - Return only the translated reply.
    - Do not translate or repeat the original message.
    - Do not translate or repeat the existing translation.
    - Do not add explanations, alternatives, markdown fences, labels, quotes, or notes.
    - Preserve paragraph breaks, list structure, URLs, code identifiers, and placeholders where possible.
    - Keep the tone appropriate for the original message and the reply draft.
    - If the reply draft is already in {{target_language}}, lightly polish it and still return only the reply.

    Context original {{source_language}} text:
    {{original}}

    Context existing translation:
    {{translation}}

    Reply draft to translate into {{target_language}}:
    {{reply}}
    """

    static let defaultReplyCorrectionTemplate = """
    You are a writing coach for a language learner.

    The user is replying in {{source_language}} to a {{source_language}} message that has already been translated into {{target_language}}.
    The user also provides the intended meaning in {{target_language}}.
    Use the original {{source_language}} message, the existing {{target_language}} translation, and the intended {{target_language}} meaning as context for meaning, references, tone, and terminology.

    Review whether the user's {{source_language}} reply draft accurately communicates the intended {{target_language}} meaning in the original context.

    Output in {{target_language}} with these sections:

    Draft meaning:
    <Natural {{target_language}} rendering of the reply draft>

    Issues:
    - <Briefly point out meaning mismatches, unnatural wording, grammar, vocabulary, nuance, or tone issues>
    - If there are no major issues, say so

    Corrected reply:
    <A natural and correct {{source_language}} reply>

    Rules:
    - Do not translate or repeat the full original message.
    - Do not translate or repeat the existing translation.
    - Keep the corrected reply faithful to the intended {{target_language}} meaning and appropriate for the original context.
    - Preserve URLs, code identifiers, and placeholders where possible.
    - Do not use markdown fences.

    Context original {{source_language}} text:
    {{original}}

    Context existing {{target_language}} translation:
    {{translation}}

    Intended meaning in {{target_language}}:
    {{intended}}

    {{source_language}} reply draft to review:
    {{reply}}
    """

    private static let templateDefaultsKey = "promptTemplate"
    private static let replyTemplateDefaultsKey = "replyPromptTemplate"
    private static let replyCorrectionTemplateDefaultsKey = "replyCorrectionPromptTemplate"
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

    static var replyCorrectionTemplate: String {
        get {
            let savedTemplate = UserDefaults.standard.string(forKey: replyCorrectionTemplateDefaultsKey) ?? ""
            return savedTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? defaultReplyCorrectionTemplate
                : savedTemplate
        }
        set {
            UserDefaults.standard.set(newValue, forKey: replyCorrectionTemplateDefaultsKey)
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

    static func resetReplyCorrectionTemplate() {
        replyCorrectionTemplate = defaultReplyCorrectionTemplate
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

    static func renderReplyCorrection(
        template: String,
        originalText: String,
        translatedText: String,
        intendedText: String,
        replyDraft: String,
        direction: TranslationDirection
    ) -> String {
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultReplyCorrectionTemplate
            : template
        var prompt = trimmedTemplate
            .replacingOccurrences(of: replyOriginalToken, with: originalText)
            .replacingOccurrences(of: replyTranslationToken, with: translatedText)
            .replacingOccurrences(of: replyDraftToken, with: replyDraft)
            .replacingOccurrences(of: replyIntendedToken, with: intendedText)
            .replacingOccurrences(of: replyTargetLanguageToken, with: direction.targetLanguage)
            .replacingOccurrences(of: replySourceLanguageToken, with: direction.sourceLanguage)

        if !prompt.contains(replyDraft) {
            prompt += "\n\n\(direction.sourceLanguage) reply draft to review:\n\(replyDraft)"
        }

        if !prompt.contains(originalText) {
            prompt += "\n\nContext original \(direction.sourceLanguage) text:\n\(originalText)"
        }

        if !prompt.contains(translatedText) {
            prompt += "\n\nContext existing \(direction.targetLanguage) translation:\n\(translatedText)"
        }

        if !prompt.contains(intendedText) {
            prompt += "\n\nIntended meaning in \(direction.targetLanguage):\n\(intendedText)"
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
