import XCTest
@testable import SelectTranslate

final class PlamoPromptTests: XCTestCase {
    func testBuildsPromptForJapaneseTarget() {
        let prompt = PlamoPrompt.make(
            text: "Open the dashboard.",
            direction: .englishToJapanese,
            form: .automatic,
            glossaryTerms: []
        )

        XCTAssertEqual(
            prompt,
            "<|plamo:tag|>dataset<|plamo:msg|>translation"
                + "<|plamo:tag|>input<|plamo:msg|>Open the dashboard."
                + "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja<|plamo:msg|>"
        )
    }

    func testAddsFormOnlyForJapaneseTarget() {
        let japanesePrompt = PlamoPrompt.make(
            text: "Hello.",
            direction: .englishToJapanese,
            form: .plain,
            glossaryTerms: []
        )
        XCTAssertTrue(japanesePrompt.hasSuffix(
            "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja<|plamo:key|>form<|plamo:val|>plain<|plamo:msg|>"
        ))

        let englishPrompt = PlamoPrompt.make(
            text: "こんにちは。",
            direction: .japaneseToEnglish,
            form: .polite,
            glossaryTerms: []
        )
        XCTAssertTrue(englishPrompt.hasSuffix("<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>"))
        XCTAssertFalse(englishPrompt.contains("form"))
        XCTAssertEqual(PlamoPrompt.effectiveForm(.polite, direction: .japaneseToEnglish), .automatic)
        XCTAssertEqual(PlamoPrompt.effectiveForm(.polite, direction: .englishToJapanese), .polite)
    }

    func testPlacesGlossaryBeforeInput() {
        let prompt = PlamoPrompt.make(
            text: "Open the dashboard.",
            direction: .englishToJapanese,
            form: .automatic,
            glossaryTerms: [PlamoGlossaryTerm(source: "dashboard", target: "管理画面")]
        )

        XCTAssertEqual(
            prompt,
            "<|plamo:tag|>dataset<|plamo:msg|>translation"
                + "<|plamo:tag|>glossary<|plamo:index|>dashboard<|plamo:item|>管理画面"
                + "<|plamo:tag|>input<|plamo:msg|>Open the dashboard."
                + "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja<|plamo:msg|>"
        )
    }

    func testGlossaryTermsFollowDirectionAndMatchSourceText() {
        let glossary = [
            PlamoGlossaryEntry(english: "Dashboard", japanese: "管理画面"),
            PlamoGlossaryEntry(english: "project", japanese: "プロジェクト"),
            PlamoGlossaryEntry(english: "", japanese: "空"),
            PlamoGlossaryEntry(english: "dashboard", japanese: "ダッシュボード")
        ]

        XCTAssertEqual(
            PlamoPrompt.glossaryTerms(for: "Open the dashboard.", direction: .englishToJapanese, glossary: glossary),
            [PlamoGlossaryTerm(source: "Dashboard", target: "管理画面")]
        )
        XCTAssertEqual(
            PlamoPrompt.glossaryTerms(for: "プロジェクトの管理画面", direction: .japaneseToEnglish, glossary: glossary),
            [
                PlamoGlossaryTerm(source: "管理画面", target: "Dashboard"),
                PlamoGlossaryTerm(source: "プロジェクト", target: "project")
            ]
        )
        XCTAssertEqual(
            PlamoPrompt.glossaryTerms(for: "Nothing here.", direction: .englishToJapanese, glossary: glossary),
            []
        )
    }

    func testRemovesReservedTokens() {
        XCTAssertEqual(PlamoPrompt.sanitized("a<|plamo:tag|>b<|plamo:msg|>c"), "abc")
        XCTAssertEqual(PlamoPrompt.sanitized("<|plamo:<|plamo:bos|>tag|>x"), "x")
        XCTAssertEqual(PlamoPrompt.sanitized("a <| b |> c"), "a <| b |> c")
        XCTAssertTrue(PlamoPrompt.containsReservedToken("<|plamo:bos|>"))
        XCTAssertFalse(PlamoPrompt.containsReservedToken("plamo"))

        let prompt = PlamoPrompt.make(
            text: "Hi<|plamo:tag|>output",
            direction: .englishToJapanese,
            form: .automatic,
            glossaryTerms: []
        )
        XCTAssertTrue(prompt.contains("<|plamo:msg|>Hioutput<|plamo:tag|>output"))
    }

    func testModelSizeRepositories() {
        XCTAssertEqual(PlamoModelSize.size0_8B.repositoryID, "pfnet/plamo-3-translate-0.8b-MLX-4bit")
        XCTAssertEqual(PlamoModelSize.size2B.repositoryID, "pfnet/plamo-3-translate-2b-MLX-4bit")
        XCTAssertEqual(PlamoModelSize.size8B.repositoryID, "pfnet/plamo-3-translate-8b-MLX-4bit")
        XCTAssertEqual(PlamoModelSize.size31B.repositoryID, "pfnet/plamo-3-translate-31b-MLX-4bit")
    }

    func testResolvedModelSizeFallsBackToInstalledSize() {
        XCTAssertEqual(PlamoSettings.resolvedModelSize(saved: .size8B, installed: [.size8B, .size2B]), .size8B)
        XCTAssertEqual(PlamoSettings.resolvedModelSize(saved: .size8B, installed: [.size2B, .size31B]), .size2B)
        XCTAssertEqual(PlamoSettings.resolvedModelSize(saved: .size8B, installed: [.size31B, .size0_8B]), .size0_8B)
        XCTAssertEqual(PlamoSettings.resolvedModelSize(saved: .size8B, installed: []), .size8B)
        XCTAssertEqual(PlamoSettings.resolvedModelSize(saved: nil, installed: []), .recommended)
    }

    func testGlossaryEntriesRoundTripThroughJSON() throws {
        let entries = [PlamoGlossaryEntry(english: "dashboard", japanese: "管理画面")]
        let decoded = try JSONDecoder().decode([PlamoGlossaryEntry].self, from: JSONEncoder().encode(entries))
        XCTAssertEqual(decoded, entries)
    }

    func testParsesMLXGenerateOutput() {
        let output = """
        ==========
        プロジェクトダッシュボードを開いてください。
        すべてのタスクが表示されます。
        ==========
        Prompt: 34 tokens, 77.251 tokens-per-sec
        Generation: 11 tokens, 154.912 tokens-per-sec
        Peak memory: 1.052 GB
        """

        XCTAssertEqual(
            CodexTranslationService.parsePlamoOutput(output, sourceText: "Open the dashboard."),
            "プロジェクトダッシュボードを開いてください。\nすべてのタスクが表示されます。"
        )
        XCTAssertEqual(
            CodexTranslationService.parsePlamoOutput("==========\n途中まで", sourceText: "x"),
            "途中まで"
        )
    }
}
