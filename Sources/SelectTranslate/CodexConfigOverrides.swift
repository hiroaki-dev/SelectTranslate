import Foundation

/// Converts Codex `config.toml` content into `key=value` lines that can be passed to `codex exec -c`.
///
/// Codex splits `-c` keys on every `.` and does not understand quoted segments, so a table whose keys
/// cannot be written as bare dotted keys is emitted as a single inline table on its parent path.
enum CodexConfigOverrides {
    struct ImportResult: Equatable {
        var lines: [String]
        var disabledKeys: [String]
    }

    struct ImportError: LocalizedError, Equatable {
        let line: Int
        let reason: String

        var errorDescription: String? {
            "Line \(line): \(reason)"
        }
    }

    /// Imported as commented-out lines because translation does not need them: `projects` lists trusted
    /// folders, which can include macOS-protected folders such as Downloads, and the others start
    /// MCP servers, plugins, or notification commands on every translation.
    static let disabledTopLevelKeys: Set<String> = ["projects", "mcp_servers", "notify", "plugins", "marketplaces"]

    static var userConfigURL: URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("config.toml")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("config.toml")
    }

    static func commandArguments(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .flatMap { ["-c", $0] }
    }

    /// Passed after user overrides so selected text sent as a prompt can never run commands with
    /// more than read-only access, whatever the user config or overrides say.
    static let enforcedArguments = ["--sandbox", "read-only", "-c", "approval_policy=\"never\""]

    struct UnsafeUserConfigError: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    /// Disables the MCP servers defined in the user config, since translation does not need them.
    ///
    /// Fails closed: `-c mcp_servers={}` does not remove configured servers, so when a server cannot be
    /// addressed with `-c` (its name needs quoting) or the config cannot be parsed, this throws instead of
    /// letting a server stay enabled unnoticed.
    static func mcpServerDisablingArguments(fromTOML text: String) throws -> [String] {
        var parser = TOMLParser(text: text)
        let root: TOMLTable
        do {
            root = try parser.parseDocument()
        } catch let error as ImportError {
            throw UnsafeUserConfigError(
                message: "Could not parse the Codex config to disable its MCP servers (\(error.localizedDescription)). Fix the file or turn off Load ~/.codex/config.toml."
            )
        }

        guard let servers = root.values["mcp_servers"] else {
            return []
        }
        guard case .table(let serverTable) = servers else {
            throw UnsafeUserConfigError(
                message: "mcp_servers in the Codex config is not a table. Fix the file or turn off Load ~/.codex/config.toml."
            )
        }

        let unaddressableNames = serverTable.keys.filter { !isBareKey($0) }
        guard unaddressableNames.isEmpty else {
            throw UnsafeUserConfigError(
                message: "MCP servers \(unaddressableNames.map(quoted).joined(separator: ", ")) in the Codex config cannot be disabled for translation because their names need quoting. Rename them or turn off Load ~/.codex/config.toml."
            )
        }
        return serverTable.keys.flatMap { ["-c", "mcp_servers.\($0).enabled=false"] }
    }

    /// Reads the user config, treating a missing file as empty like Codex does.
    static func userConfigText() throws -> String {
        let url = userConfigURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func importLines(fromTOML text: String) throws -> ImportResult {
        var parser = TOMLParser(text: text)
        let root = try parser.parseDocument()
        var result = ImportResult(lines: [], disabledKeys: [])
        for key in root.keys {
            guard let value = root.values[key] else { continue }
            // A top-level key that needs quoting cannot be expressed as a `-c` path at all.
            let isDisabled = disabledTopLevelKeys.contains(key) || !isBareKey(key)
            if isDisabled {
                result.disabledKeys.append(key)
            }
            var lines: [String] = []
            flatten(value, path: [key], into: &lines)
            result.lines.append(contentsOf: isDisabled ? lines.map { "# " + $0 } : lines)
        }
        return result
    }

    private static func flatten(_ value: TOMLValue, path: [String], into lines: inout [String]) {
        guard case .table(let table) = value,
              !table.keys.contains(where: { !isBareKey($0) }) else {
            lines.append(path.joined(separator: ".") + "=" + value.inlineText)
            return
        }

        for key in table.keys {
            guard let child = table.values[key] else { continue }
            flatten(child, path: path + [key], into: &lines)
        }
    }

    fileprivate static func isBareKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || scalar == "_" || scalar == "-"
        }
    }

    fileprivate static func quoted(_ string: String) -> String {
        var text = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\t": text += "\\t"
            case "\r": text += "\\r"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    text += String(format: "\\u%04X", scalar.value)
                } else {
                    text.unicodeScalars.append(scalar)
                }
            }
        }
        return text + "\""
    }
}

private final class TOMLTable {
    private(set) var keys: [String] = []
    private(set) var values: [String: TOMLValue] = [:]

    func set(_ key: String, _ value: TOMLValue) {
        if values[key] == nil {
            keys.append(key)
        }
        values[key] = value
    }

    var inlineText: String {
        let entries = keys.compactMap { key -> String? in
            guard let value = values[key] else { return nil }
            let keyText = CodexConfigOverrides.isBareKey(key) ? key : CodexConfigOverrides.quoted(key)
            return "\(keyText) = \(value.inlineText)"
        }
        return "{" + entries.joined(separator: ", ") + "}"
    }
}

private enum TOMLValue {
    case string(String)
    /// Numbers, booleans, and dates, kept as written.
    case literal(String)
    case array([TOMLValue])
    case table(TOMLTable)
    case tableArray([TOMLTable])

    var inlineText: String {
        switch self {
        case .string(let string):
            return CodexConfigOverrides.quoted(string)
        case .literal(let text):
            return text
        case .array(let values):
            return "[" + values.map(\.inlineText).joined(separator: ", ") + "]"
        case .table(let table):
            return table.inlineText
        case .tableArray(let tables):
            return "[" + tables.map(\.inlineText).joined(separator: ", ") + "]"
        }
    }
}

private struct TOMLParser {
    private let characters: [Character]
    private var index = 0
    private var line = 1

    init(text: String) {
        characters = Array(text)
    }

    mutating func parseDocument() throws -> TOMLTable {
        let root = TOMLTable()
        var current = root

        while true {
            skipWhitespaceCommentsAndNewlines()
            guard let character = peek() else { break }

            if character == "[" {
                if peek(offset: 1) == "[" {
                    advance(2)
                    let key = try parseKey()
                    try expect("]")
                    try expect("]")
                    current = try appendTableArray(at: key, in: root)
                } else {
                    advance()
                    let key = try parseKey()
                    try expect("]")
                    current = try table(at: key, in: root)
                }
            } else {
                try parseKeyValue(into: current)
            }

            skipInlineWhitespace()
            skipComment()
            if let next = peek() {
                guard next.isNewline else {
                    throw error("Expected a new line after the value")
                }
                advance()
            }
        }

        return root
    }

    private mutating func parseKeyValue(into table: TOMLTable) throws {
        let key = try parseKey()
        try expect("=")
        skipInlineWhitespace()
        let value = try parseValue()
        let parent = try self.table(at: Array(key.dropLast()), in: table)
        guard let lastKey = key.last, parent.values[lastKey] == nil else {
            throw error("Duplicate key")
        }
        parent.set(lastKey, value)
    }

    private mutating func parseKey() throws -> [String] {
        var segments: [String] = []
        while true {
            skipInlineWhitespace()
            switch peek() {
            case "\"":
                segments.append(try parseBasicString())
            case "'":
                segments.append(try parseLiteralString())
            default:
                var segment = ""
                while let character = peek(),
                      character.isASCII && (character.isLetter || character.isNumber) || character == "_" || character == "-" {
                    segment.append(character)
                    advance()
                }
                guard !segment.isEmpty else {
                    throw error("Expected a key")
                }
                segments.append(segment)
            }
            skipInlineWhitespace()
            guard peek() == "." else { return segments }
            advance()
        }
    }

    private mutating func parseValue() throws -> TOMLValue {
        switch peek() {
        case "\"":
            if peek(offset: 1) == "\"", peek(offset: 2) == "\"" {
                return .string(try parseMultilineString(quote: "\"", allowsEscapes: true))
            }
            return .string(try parseBasicString())
        case "'":
            if peek(offset: 1) == "'", peek(offset: 2) == "'" {
                return .string(try parseMultilineString(quote: "'", allowsEscapes: false))
            }
            return .string(try parseLiteralString())
        case "[":
            return try parseArray()
        case "{":
            return .table(try parseInlineTable())
        default:
            var text = ""
            while let character = peek(), !character.isNewline, !",]}#".contains(character) {
                text.append(character)
                advance()
            }
            text = text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else {
                throw error("Expected a value")
            }
            return .literal(text)
        }
    }

    private mutating func parseArray() throws -> TOMLValue {
        advance()
        var values: [TOMLValue] = []
        while true {
            skipWhitespaceCommentsAndNewlines()
            if peek() == "]" {
                advance()
                return .array(values)
            }
            values.append(try parseValue())
            skipWhitespaceCommentsAndNewlines()
            switch peek() {
            case ",":
                advance()
            case "]":
                advance()
                return .array(values)
            default:
                throw error("Expected ',' or ']' in array")
            }
        }
    }

    private mutating func parseInlineTable() throws -> TOMLTable {
        advance()
        let table = TOMLTable()
        skipWhitespaceCommentsAndNewlines()
        if peek() == "}" {
            advance()
            return table
        }
        while true {
            try parseKeyValue(into: table)
            skipWhitespaceCommentsAndNewlines()
            switch peek() {
            case ",":
                advance()
                skipWhitespaceCommentsAndNewlines()
            case "}":
                advance()
                return table
            default:
                throw error("Expected ',' or '}' in inline table")
            }
        }
    }

    private mutating func parseBasicString() throws -> String {
        advance()
        var text = ""
        while let character = peek() {
            switch character {
            case "\"":
                advance()
                return text
            case "\\":
                text.append(contentsOf: try parseEscape())
            default:
                guard !character.isNewline else {
                    throw error("Unterminated string")
                }
                text.append(character)
                advance()
            }
        }
        throw error("Unterminated string")
    }

    private mutating func parseLiteralString() throws -> String {
        advance()
        var text = ""
        while let character = peek() {
            if character == "'" {
                advance()
                return text
            }
            guard !character.isNewline else {
                throw error("Unterminated string")
            }
            text.append(character)
            advance()
        }
        throw error("Unterminated string")
    }

    private mutating func parseMultilineString(quote: Character, allowsEscapes: Bool) throws -> String {
        advance(3)
        if peek()?.isNewline == true {
            advance()
        }
        var text = ""
        while let character = peek() {
            if character == quote, peek(offset: 1) == quote, peek(offset: 2) == quote {
                var count = 3
                while peek(offset: count) == quote, count < 5 {
                    count += 1
                }
                text.append(String(repeating: quote, count: count - 3))
                advance(count)
                return text
            }
            if allowsEscapes, character == "\\" {
                if isLineEndingBackslash() {
                    advance()
                    while let next = peek(), next == " " || next == "\t" || next.isNewline {
                        advance()
                    }
                } else {
                    text.append(contentsOf: try parseEscape())
                }
                continue
            }
            text.append(character)
            advance()
        }
        throw error("Unterminated multi-line string")
    }

    private func isLineEndingBackslash() -> Bool {
        var offset = 1
        while let next = peek(offset: offset), next == " " || next == "\t" {
            offset += 1
        }
        return peek(offset: offset)?.isNewline == true
    }

    private mutating func parseEscape() throws -> String {
        advance()
        guard let character = peek() else {
            throw error("Unterminated escape sequence")
        }
        advance()
        switch character {
        case "b": return "\u{08}"
        case "t": return "\t"
        case "n": return "\n"
        case "f": return "\u{0C}"
        case "r": return "\r"
        case "e": return "\u{1B}"
        case "\"": return "\""
        case "\\": return "\\"
        case "u", "U":
            let length = character == "u" ? 4 : 8
            var hex = ""
            for _ in 0..<length {
                guard let digit = peek(), digit.isHexDigit else {
                    throw error("Invalid unicode escape")
                }
                hex.append(digit)
                advance()
            }
            guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else {
                throw error("Invalid unicode escape")
            }
            return String(scalar)
        default:
            throw error("Invalid escape sequence")
        }
    }

    private func table(at path: [String], in root: TOMLTable) throws -> TOMLTable {
        var current = root
        for segment in path {
            switch current.values[segment] {
            case .table(let table):
                current = table
            case .tableArray(let tables):
                guard let last = tables.last else {
                    throw error("Invalid table '\(segment)'")
                }
                current = last
            case nil:
                let table = TOMLTable()
                current.set(segment, .table(table))
                current = table
            default:
                throw error("'\(segment)' is not a table")
            }
        }
        return current
    }

    private func appendTableArray(at path: [String], in root: TOMLTable) throws -> TOMLTable {
        guard let lastKey = path.last else {
            throw error("Expected a key")
        }
        let parent = try table(at: Array(path.dropLast()), in: root)
        let table = TOMLTable()
        switch parent.values[lastKey] {
        case .tableArray(let tables):
            parent.set(lastKey, .tableArray(tables + [table]))
        case nil:
            parent.set(lastKey, .tableArray([table]))
        default:
            throw error("'\(lastKey)' is not an array of tables")
        }
        return table
    }

    private mutating func expect(_ character: Character) throws {
        skipInlineWhitespace()
        guard peek() == character else {
            throw error("Expected '\(character)'")
        }
        advance()
    }

    private mutating func skipInlineWhitespace() {
        while let character = peek(), character == " " || character == "\t" {
            advance()
        }
    }

    private mutating func skipComment() {
        guard peek() == "#" else { return }
        while let character = peek(), !character.isNewline {
            advance()
        }
    }

    private mutating func skipWhitespaceCommentsAndNewlines() {
        while let character = peek() {
            if character == " " || character == "\t" || character.isNewline {
                advance()
            } else if character == "#" {
                skipComment()
            } else {
                return
            }
        }
    }

    private func peek(offset: Int = 0) -> Character? {
        let position = index + offset
        return position < characters.count ? characters[position] : nil
    }

    private mutating func advance(_ count: Int = 1) {
        for _ in 0..<count where index < characters.count {
            if characters[index].isNewline {
                line += 1
            }
            index += 1
        }
    }

    private func error(_ reason: String) -> CodexConfigOverrides.ImportError {
        CodexConfigOverrides.ImportError(line: line, reason: reason)
    }
}
