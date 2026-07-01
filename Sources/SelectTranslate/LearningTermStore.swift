import Foundation
import SQLite3

enum LearningTermSourceKind: String, CaseIterable {
    case original
    case translatedReply

    var label: String {
        switch self {
        case .original:
            return "Original"
        case .translatedReply:
            return "Translated reply"
        }
    }
}

struct LearningTerm: Identifiable, Equatable {
    let id: Int64
    let createdAt: Date
    let text: String
    let translation: String
    let sourceKind: LearningTermSourceKind
    let directionLabel: String
    let engineLabel: String
    let historyID: Int64?
}

final class LearningTermStore {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL = AppPaths.learningTermsDatabaseURL) {
        self.databaseURL = databaseURL
        do {
            try openDatabase()
            try migrateIfNeeded()
        } catch {
            NSLog("SelectTranslate learning term database initialization failed: \(error.localizedDescription)")
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func loadTerms(limit: Int = 1000) -> [LearningTerm] {
        do {
            try openDatabase()
            let sql = """
            SELECT id, created_at, text, translation, source_kind, direction_label, engine_label, history_id
            FROM learning_terms
            ORDER BY created_at DESC, id DESC
            LIMIT ?;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(limit))

            var terms: [LearningTerm] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                terms.append(term(from: statement))
            }
            return terms
        } catch {
            NSLog("SelectTranslate learning term load failed: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    func upsert(
        text: String,
        translation: String,
        sourceKind: LearningTermSourceKind,
        directionLabel: String,
        engineLabel: String,
        historyID: Int64?,
        createdAt: Date = Date()
    ) -> LearningTerm? {
        let normalizedText = Self.normalizedText(text)
        guard !normalizedText.isEmpty else {
            return nil
        }

        do {
            try openDatabase()
            let sql = """
            INSERT INTO learning_terms (
                created_at,
                text,
                normalized_text,
                translation,
                source_kind,
                direction_label,
                engine_label,
                history_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(normalized_text, source_kind)
            DO UPDATE SET
                created_at = excluded.created_at,
                text = excluded.text,
                translation = excluded.translation,
                direction_label = excluded.direction_label,
                engine_label = excluded.engine_label,
                history_id = excluded.history_id;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, createdAt.timeIntervalSince1970)
            bindText(text.trimmingCharacters(in: .whitespacesAndNewlines), to: statement, at: 2)
            bindText(normalizedText, to: statement, at: 3)
            bindText(translation.trimmingCharacters(in: .whitespacesAndNewlines), to: statement, at: 4)
            bindText(sourceKind.rawValue, to: statement, at: 5)
            bindText(directionLabel, to: statement, at: 6)
            bindText(engineLabel, to: statement, at: 7)
            if let historyID {
                sqlite3_bind_int64(statement, 8, historyID)
            } else {
                sqlite3_bind_null(statement, 8)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteLearningTermError.step(message: lastErrorMessage)
            }

            return loadTerm(normalizedText: normalizedText, sourceKind: sourceKind)
        } catch {
            NSLog("SelectTranslate learning term upsert failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func normalizedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: [.regularExpression]
            )
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
            throw SQLiteLearningTermError.open(
                message: openedDatabase.map(Self.errorMessage(for:)) ?? "Unable to open database."
            )
        }

        database = openedDatabase
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    private func migrateIfNeeded() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS learning_terms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            text TEXT NOT NULL,
            normalized_text TEXT NOT NULL,
            translation TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            direction_label TEXT NOT NULL,
            engine_label TEXT NOT NULL,
            history_id INTEGER
        );
        """)
        try execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_learning_terms_normalized_source
        ON learning_terms(normalized_text, source_kind);
        """)
        try execute("""
        CREATE INDEX IF NOT EXISTS idx_learning_terms_created_at
        ON learning_terms(created_at DESC, id DESC);
        """)
    }

    private func loadTerm(normalizedText: String, sourceKind: LearningTermSourceKind) -> LearningTerm? {
        do {
            try openDatabase()
            let sql = """
            SELECT id, created_at, text, translation, source_kind, direction_label, engine_label, history_id
            FROM learning_terms
            WHERE normalized_text = ? AND source_kind = ?
            LIMIT 1;
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            bindText(normalizedText, to: statement, at: 1)
            bindText(sourceKind.rawValue, to: statement, at: 2)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }

            return term(from: statement)
        } catch {
            NSLog("SelectTranslate learning term item load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func term(from statement: OpaquePointer?) -> LearningTerm {
        let sourceKind = LearningTermSourceKind(rawValue: columnText(statement, 4)) ?? .original
        let historyID = sqlite3_column_type(statement, 7) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(statement, 7)
        return LearningTerm(
            id: sqlite3_column_int64(statement, 0),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            text: columnText(statement, 2),
            translation: columnText(statement, 3),
            sourceKind: sourceKind,
            directionLabel: columnText(statement, 5),
            engineLabel: columnText(statement, 6),
            historyID: historyID
        )
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw SQLiteLearningTermError.open(message: "Database is not open.") }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteLearningTermError.step(message: lastErrorMessage)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else { throw SQLiteLearningTermError.open(message: "Database is not open.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteLearningTermError.prepare(message: lastErrorMessage)
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

private enum SQLiteLearningTermError: LocalizedError {
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
