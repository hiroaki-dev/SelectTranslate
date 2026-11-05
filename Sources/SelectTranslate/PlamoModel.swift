import Foundation

extension Notification.Name {
    static let plamoSettingsDidChange = Notification.Name("SelectTranslatePlamoSettingsDidChange")
}

/// PLaMo 3 Translate sizes, using the official MLX 4-bit builds from Preferred Networks.
enum PlamoModelSize: String, CaseIterable, Identifiable, Hashable, Codable {
    case size0_8B = "0.8b"
    case size2B = "2b"
    case size8B = "8b"
    case size31B = "31b"

    static let recommended: PlamoModelSize = .size2B

    var id: String { rawValue }

    var label: String {
        switch self {
        case .size0_8B:
            return "0.8B"
        case .size2B:
            return "2B"
        case .size8B:
            return "8B"
        case .size31B:
            return "31B"
        }
    }

    var repositoryID: String {
        "pfnet/plamo-3-translate-\(rawValue)-MLX-4bit"
    }

    var approximateDownloadSize: String {
        switch self {
        case .size0_8B:
            return "1.0 GB"
        case .size2B:
            return "2.4 GB"
        case .size8B:
            return "6.1 GB"
        case .size31B:
            return "18.7 GB"
        }
    }
}

/// PLaMo 3 `form` option. It only applies when the target language is Japanese.
enum PlamoJapaneseForm: String, CaseIterable, Identifiable, Hashable {
    case automatic
    case polite
    case plain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic:
            return "Auto"
        case .polite:
            return "Polite"
        case .plain:
            return "Plain"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Let the model choose"
        case .polite:
            return "です・ます調"
        case .plain:
            return "だ・である調"
        }
    }

    /// Value written to the PFML3 `form` attribute, or nil to omit it.
    var promptValue: String? {
        switch self {
        case .automatic:
            return nil
        case .polite:
            return "polite"
        case .plain:
            return "plain"
        }
    }
}

/// An English/Japanese term pair. The pair is used in both translation directions.
struct PlamoGlossaryEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var english: String
    var japanese: String

    init(id: UUID = UUID(), english: String = "", japanese: String = "") {
        self.id = id
        self.english = english
        self.japanese = japanese
    }
}

/// A glossary term in the form PLaMo receives it for one translation.
struct PlamoGlossaryTerm: Hashable {
    let source: String
    let target: String
}

enum PlamoSettings {
    private static let modelSizeDefaultsKey = "plamoModelSize"
    private static let japaneseFormDefaultsKey = "plamoJapaneseForm"
    private static let glossaryDefaultsKey = "plamoGlossary"

    /// The size used for translation. Falls back to an installed size when the saved one is not installed.
    static var selectedModelSize: PlamoModelSize {
        get {
            resolvedModelSize(
                saved: savedModelSize,
                installed: PlamoSetupService.installedModelSizes
            )
        }
        set {
            guard newValue != savedModelSize else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: modelSizeDefaultsKey)
            NotificationCenter.default.post(name: .plamoSettingsDidChange, object: nil)
        }
    }

    static var japaneseForm: PlamoJapaneseForm {
        get {
            UserDefaults.standard.string(forKey: japaneseFormDefaultsKey)
                .flatMap(PlamoJapaneseForm.init(rawValue:)) ?? .automatic
        }
        set {
            guard newValue != japaneseForm else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: japaneseFormDefaultsKey)
            NotificationCenter.default.post(name: .plamoSettingsDidChange, object: nil)
        }
    }

    static var glossary: [PlamoGlossaryEntry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: glossaryDefaultsKey),
                  let entries = try? JSONDecoder().decode([PlamoGlossaryEntry].self, from: data) else {
                return []
            }
            return entries
        }
        set {
            guard newValue != glossary, let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: glossaryDefaultsKey)
            NotificationCenter.default.post(name: .plamoSettingsDidChange, object: nil)
        }
    }

    static func resolvedModelSize(saved: PlamoModelSize?, installed: Set<PlamoModelSize>) -> PlamoModelSize {
        if let saved, installed.contains(saved) {
            return saved
        }
        if installed.contains(.recommended) {
            return .recommended
        }
        if let firstInstalled = PlamoModelSize.allCases.first(where: installed.contains) {
            return firstInstalled
        }
        return saved ?? .recommended
    }

    private static var savedModelSize: PlamoModelSize? {
        UserDefaults.standard.string(forKey: modelSizeDefaultsKey).flatMap(PlamoModelSize.init(rawValue:))
    }
}

/// Builds PLaMo 3 prompts in the PFML3 format.
enum PlamoPrompt {
    /// Builds the prompt without the BOS token, which the tokenizer adds.
    /// The source language is omitted so that PLaMo detects it, which also lets it translate
    /// languages other than English into Japanese.
    static func make(
        text: String,
        direction: TranslationDirection,
        form: PlamoJapaneseForm,
        glossaryTerms: [PlamoGlossaryTerm]
    ) -> String {
        var prompt = "<|plamo:tag|>dataset<|plamo:msg|>translation"

        if !glossaryTerms.isEmpty {
            prompt += "<|plamo:tag|>glossary"
            for term in glossaryTerms {
                prompt += "<|plamo:index|>\(term.source)<|plamo:item|>\(term.target)"
            }
        }

        let targetLanguage = targetLanguageCode(for: direction)
        prompt += "<|plamo:tag|>input<|plamo:msg|>\(sanitized(text))"
        prompt += "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>\(targetLanguage)"
        if let formValue = effectiveForm(form, direction: direction).promptValue {
            prompt += "<|plamo:key|>form<|plamo:val|>\(formValue)"
        }
        prompt += "<|plamo:msg|>"
        return prompt
    }

    static func targetLanguageCode(for direction: TranslationDirection) -> String {
        switch direction {
        case .englishToJapanese:
            return "ja"
        case .japaneseToEnglish:
            return "en"
        }
    }

    /// PLaMo 3 accepts `form` only for Japanese output.
    static func effectiveForm(_ form: PlamoJapaneseForm, direction: TranslationDirection) -> PlamoJapaneseForm {
        direction == .englishToJapanese ? form : .automatic
    }

    /// Returns the glossary terms whose source term appears in the text, oriented for the direction.
    static func glossaryTerms(
        for text: String,
        direction: TranslationDirection,
        glossary: [PlamoGlossaryEntry]
    ) -> [PlamoGlossaryTerm] {
        var seenSources = Set<String>()
        var terms: [PlamoGlossaryTerm] = []

        for entry in glossary {
            let english = sanitized(entry.english).trimmingCharacters(in: .whitespacesAndNewlines)
            let japanese = sanitized(entry.japanese).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty, !japanese.isEmpty else { continue }

            let term: PlamoGlossaryTerm
            switch direction {
            case .englishToJapanese:
                term = PlamoGlossaryTerm(source: english, target: japanese)
            case .japaneseToEnglish:
                term = PlamoGlossaryTerm(source: japanese, target: english)
            }

            let sourceKey = term.source.lowercased()
            guard !seenSources.contains(sourceKey),
                  text.range(of: term.source, options: [.caseInsensitive]) != nil else {
                continue
            }
            seenSources.insert(sourceKey)
            terms.append(term)
        }

        return terms
    }

    static func containsReservedToken(_ text: String) -> Bool {
        text.range(of: reservedTokenPattern, options: .regularExpression) != nil
    }

    /// Removes PFML reserved tokens such as `<|plamo:tag|>` so that user text cannot change the prompt structure.
    static func sanitized(_ text: String) -> String {
        // Repeat so that removing one token cannot join the surrounding text into another token.
        var result = text
        while containsReservedToken(result) {
            result = result.replacingOccurrences(of: reservedTokenPattern, with: "", options: .regularExpression)
        }
        return result
    }

    private static let reservedTokenPattern = #"<\|plamo:[^|>]*\|>"#
}
