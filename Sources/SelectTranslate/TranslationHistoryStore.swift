import Foundation
import SQLite3

struct TranslationHistoryItem: Identifiable, Equatable {
    let id: Int64
    let createdAt: Date
    let originalText: String
    let translatedText: String
    let engineLabel: String
    let providerRawValue: String
    let directionLabel: String
    let replyDraftText: String
    let translatedReplyText: String
    let replyMode: ReplyWorkflowMode

    var originalPreview: String {
        let lines = originalText.components(separatedBy: .newlines)
        let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasAdditionalLines = lines.dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let needsEllipsis = firstLine.count > 20 || hasAdditionalLines
        let preview = firstLine.count > 20 ? String(firstLine.prefix(20)) : firstLine
        return needsEllipsis ? "\(preview)..." : preview
    }
}

final class TranslationHistoryStore {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL = AppPaths.translationHistoryDatabaseURL) {
        self.databaseURL = databaseURL
        do {
            try openDatabase()
            try migrateIfNeeded()
        } catch {
            NSLog("SelectTranslate history database initialization failed: \(error.localizedDescription)")
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func loadItems(limit: Int = 200) -> [TranslationHistoryItem] {
        do {
            try openDatabase()
            let sql = """
            SELECT id, created_at, original_text, translated_text, engine_label, provider_raw_value, direction_label,
                   reply_draft_text, translated_reply_text, reply_mode
            FROM translation_history
            ORDER BY created_at DESC, id DESC
            LIMIT ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(limit))

            var items: [TranslationHistoryItem] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                items.append(
                    TranslationHistoryItem(
                        id: sqlite3_column_int64(statement, 0),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                        originalText: columnText(statement, 2),
                        translatedText: columnText(statement, 3),
                        engineLabel: columnText(statement, 4),
                        providerRawValue: columnText(statement, 5),
                        directionLabel: columnText(statement, 6),
                        replyDraftText: columnText(statement, 7),
                        translatedReplyText: columnText(statement, 8),
                        replyMode: ReplyWorkflowMode(rawValue: columnText(statement, 9)) ?? .translation
                    )
                )
            }
            return items
        } catch {
            NSLog("SelectTranslate history load failed: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    func insert(
        originalText: String,
        translatedText: String,
        engineLabel: String,
        providerRawValue: String,
        directionLabel: String,
        createdAt: Date = Date()
    ) -> TranslationHistoryItem? {
        do {
            try openDatabase()
            let sql = """
            INSERT INTO translation_history (
                created_at,
                original_text,
                translated_text,
                engine_label,
                provider_raw_value,
                direction_label
            ) VALUES (?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, createdAt.timeIntervalSince1970)
            bindText(originalText, to: statement, at: 2)
            bindText(translatedText, to: statement, at: 3)
            bindText(engineLabel, to: statement, at: 4)
            bindText(providerRawValue, to: statement, at: 5)
            bindText(directionLabel, to: statement, at: 6)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteHistoryError.step(message: lastErrorMessage)
            }

            return TranslationHistoryItem(
                id: sqlite3_last_insert_rowid(database),
                createdAt: createdAt,
                originalText: originalText,
                translatedText: translatedText,
                engineLabel: engineLabel,
                providerRawValue: providerRawValue,
                directionLabel: directionLabel,
                replyDraftText: "",
                translatedReplyText: "",
                replyMode: .translation
            )
        } catch {
            NSLog("SelectTranslate history insert failed: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func updateReply(
        id: Int64,
        replyDraftText: String,
        translatedReplyText: String,
        replyMode: ReplyWorkflowMode
    ) -> TranslationHistoryItem? {
        do {
            try openDatabase()
            let sql = """
            UPDATE translation_history
            SET reply_draft_text = ?, translated_reply_text = ?, reply_mode = ?
            WHERE id = ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            bindText(replyDraftText, to: statement, at: 1)
            bindText(translatedReplyText, to: statement, at: 2)
            bindText(replyMode.rawValue, to: statement, at: 3)
            sqlite3_bind_int64(statement, 4, id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteHistoryError.step(message: lastErrorMessage)
            }

            return loadItem(id: id)
        } catch {
            NSLog("SelectTranslate history reply update failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func openDatabase() throws {
        guard database == nil else { return }

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var openedDatabase: OpaquePointer?
        let status = sqlite3_open_v2(
            databaseURL.path,
            &openedDatabase,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK, let openedDatabase else {
            throw SQLiteHistoryError.open(message: openedDatabase.map(Self.errorMessage(for:)) ?? "Unable to open database.")
        }

        database = openedDatabase
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    private func migrateIfNeeded() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS translation_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            original_text TEXT NOT NULL,
            translated_text TEXT NOT NULL,
            engine_label TEXT NOT NULL,
            provider_raw_value TEXT NOT NULL,
            direction_label TEXT NOT NULL
        );
        """)
        try addColumnIfNeeded(
            tableName: "translation_history",
            columnName: "reply_draft_text",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        try addColumnIfNeeded(
            tableName: "translation_history",
            columnName: "translated_reply_text",
            definition: "TEXT NOT NULL DEFAULT ''"
        )
        try addColumnIfNeeded(
            tableName: "translation_history",
            columnName: "reply_mode",
            definition: "TEXT NOT NULL DEFAULT 'translation'"
        )
        try execute("""
        CREATE INDEX IF NOT EXISTS idx_translation_history_created_at
        ON translation_history(created_at DESC, id DESC);
        """)
    }

    private func loadItem(id: Int64) -> TranslationHistoryItem? {
        do {
            try openDatabase()
            let sql = """
            SELECT id, created_at, original_text, translated_text, engine_label, provider_raw_value, direction_label,
                   reply_draft_text, translated_reply_text, reply_mode
            FROM translation_history
            WHERE id = ?
            LIMIT 1;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, id)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            return TranslationHistoryItem(
                id: sqlite3_column_int64(statement, 0),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                originalText: columnText(statement, 2),
                translatedText: columnText(statement, 3),
                engineLabel: columnText(statement, 4),
                providerRawValue: columnText(statement, 5),
                directionLabel: columnText(statement, 6),
                replyDraftText: columnText(statement, 7),
                translatedReplyText: columnText(statement, 8),
                replyMode: ReplyWorkflowMode(rawValue: columnText(statement, 9)) ?? .translation
            )
        } catch {
            NSLog("SelectTranslate history item load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func addColumnIfNeeded(tableName: String, columnName: String, definition: String) throws {
        guard try !tableHasColumn(tableName: tableName, columnName: columnName) else {
            return
        }

        try execute("ALTER TABLE \(tableName) ADD COLUMN \(columnName) \(definition);")
    }

    private func tableHasColumn(tableName: String, columnName: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(tableName));")
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, 1) == columnName {
                return true
            }
        }

        return false
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw SQLiteHistoryError.open(message: "Database is not open.") }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteHistoryError.step(message: lastErrorMessage)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else { throw SQLiteHistoryError.open(message: "Database is not open.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteHistoryError.prepare(message: lastErrorMessage)
        }
        return statement
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private var lastErrorMessage: String {
        guard let database else { return "Database is not open." }
        return Self.errorMessage(for: database)
    }

    private static func errorMessage(for database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else { return "Unknown SQLite error." }
        return String(cString: message)
    }
}

private enum SQLiteHistoryError: LocalizedError {
    case open(message: String)
    case prepare(message: String)
    case step(message: String)

    var errorDescription: String? {
        switch self {
        case let .open(message):
            return "SQLite open failed: \(message)"
        case let .prepare(message):
            return "SQLite prepare failed: \(message)"
        case let .step(message):
            return "SQLite operation failed: \(message)"
        }
    }
}
