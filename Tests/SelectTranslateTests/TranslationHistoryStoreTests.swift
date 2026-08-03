import Foundation
import XCTest
@testable import SelectTranslate

final class TranslationHistoryStoreTests: XCTestCase {
    private var databaseURL: URL!
    private var store: TranslationHistoryStore!

    override func setUpWithError() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelectTranslateTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite3")
        store = TranslationHistoryStore(databaseURL: databaseURL)
    }

    override func tearDownWithError() throws {
        store = nil
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
        databaseURL = nil
    }

    func testSearchMatchesAllSearchableColumnsAndTrimsQuery() throws {
        let original = try insert(original: "needle in original", translation: "translated one", createdAt: 1)
        let translated = try insert(original: "original two", translation: "needle in translation", createdAt: 2)
        let replyDraft = try insert(original: "original three", translation: "translated three", createdAt: 3)
        let replyIntent = try insert(original: "original four", translation: "translated four", createdAt: 4)
        let translatedReply = try insert(original: "original five", translation: "translated five", createdAt: 5)

        XCTAssertNotNil(store.updateReply(
            id: replyDraft.id,
            replyDraftText: "needle in reply draft",
            replyIntentText: "",
            translatedReplyText: "",
            replyMode: .translation
        ))
        XCTAssertNotNil(store.updateReply(
            id: replyIntent.id,
            replyDraftText: "",
            replyIntentText: "needle in reply intent",
            translatedReplyText: "",
            replyMode: .correction
        ))
        XCTAssertNotNil(store.updateReply(
            id: translatedReply.id,
            replyDraftText: "",
            replyIntentText: "",
            translatedReplyText: "needle in translated reply",
            replyMode: .translation
        ))

        XCTAssertEqual(
            store.loadItems(matching: "  needle  ").map(\.id),
            [translatedReply.id, replyIntent.id, replyDraft.id, translated.id, original.id]
        )
    }

    func testSearchTreatsLikeWildcardsAndEscapeCharacterLiterally() throws {
        let percent = try insert(original: "Save 100% today", translation: "percent")
        let underscore = try insert(original: "file_name", translation: "underscore")
        let backslash = try insert(original: #"C:\\Users\\yuki"#, translation: "backslash")
        _ = try insert(original: "ordinary text", translation: "no symbols")

        XCTAssertEqual(store.loadItems(matching: "%").map(\.id), [percent.id])
        XCTAssertEqual(store.loadItems(matching: "_").map(\.id), [underscore.id])
        XCTAssertEqual(store.loadItems(matching: #"\"#).map(\.id), [backslash.id])
    }

    func testEmptySearchReturnsMostRecentTwoHundredItemsInDescendingOrder() throws {
        var ids: [Int64] = []
        for index in 0..<201 {
            let item = try insert(
                original: "original \(index)",
                translation: "translation \(index)",
                createdAt: TimeInterval(index)
            )
            ids.append(item.id)
        }

        let items = store.loadItems(matching: "  ", limit: 300)

        XCTAssertEqual(items.count, 200)
        XCTAssertEqual(items.map(\.id), Array(ids.dropFirst().reversed()))
    }

    func testSearchOrdersMatchingItemsByCreatedAtThenIDAndLimitsResults() throws {
        let oldest = try insert(original: "match oldest", translation: "", createdAt: 1)
        let sameTimeFirst = try insert(original: "match first", translation: "", createdAt: 2)
        let sameTimeSecond = try insert(original: "match second", translation: "", createdAt: 2)
        let newest = try insert(original: "match newest", translation: "", createdAt: 3)

        XCTAssertEqual(
            store.loadItems(matching: "match", limit: 3).map(\.id),
            [newest.id, sameTimeSecond.id, sameTimeFirst.id]
        )
        XCTAssertFalse(store.loadItems(matching: "match", limit: 3).contains(where: { $0.id == oldest.id }))
    }

    @discardableResult
    private func insert(
        original: String,
        translation: String,
        createdAt: TimeInterval = 0
    ) throws -> TranslationHistoryItem {
        try XCTUnwrap(store.insert(
            originalText: original,
            translatedText: translation,
            engineLabel: "Test",
            providerRawValue: "test",
            directionLabel: "English → Japanese",
            createdAt: Date(timeIntervalSince1970: createdAt)
        ))
    }
}
