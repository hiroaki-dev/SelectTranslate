import Carbon
import Foundation

extension Notification.Name {
    static let shortcutProfilesDidChange = Notification.Name("SelectTranslateShortcutProfilesDidChange")
}

struct ShortcutProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var keyCode: UInt32
    var modifiers: UInt32
    var promptTemplate: String

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled Shortcut" : trimmedName
    }

    var shortcut: KeyboardShortcut {
        KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    var shortcutLabel: String {
        shortcut.label
    }

    var normalizedPromptTemplate: String {
        promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? PromptSettings.defaultTemplate
            : promptTemplate
    }

    static func defaultProfile(promptTemplate: String = PromptSettings.defaultTemplate) -> ShortcutProfile {
        ShortcutProfile(
            id: "default",
            name: "Default",
            keyCode: KeyboardShortcut.defaultKeyCode,
            modifiers: KeyboardShortcutModifier.control.mask,
            promptTemplate: promptTemplate
        )
    }
}

struct KeyboardShortcut: Codable, Equatable, Hashable {
    static let defaultKeyCode = UInt32(kVK_ANSI_F)

    var keyCode: UInt32
    var modifiers: UInt32

    var normalizedModifiers: UInt32 {
        modifiers & KeyboardShortcutModifier.allMask
    }

    var storageKey: String {
        "\(keyCode):\(normalizedModifiers)"
    }

    var label: String {
        let modifierLabels = KeyboardShortcutModifier.allCases
            .filter { normalizedModifiers & $0.mask != 0 }
            .map(\.label)
        let keyLabel = Self.label(for: keyCode) ?? "Key \(keyCode)"
        return (modifierLabels + [keyLabel]).joined(separator: " + ")
    }

    static let keyOptions: [KeyboardShortcutKeyOption] = [
        .init(label: "A", keyCode: UInt32(kVK_ANSI_A)),
        .init(label: "B", keyCode: UInt32(kVK_ANSI_B)),
        .init(label: "C", keyCode: UInt32(kVK_ANSI_C)),
        .init(label: "D", keyCode: UInt32(kVK_ANSI_D)),
        .init(label: "E", keyCode: UInt32(kVK_ANSI_E)),
        .init(label: "F", keyCode: UInt32(kVK_ANSI_F)),
        .init(label: "G", keyCode: UInt32(kVK_ANSI_G)),
        .init(label: "H", keyCode: UInt32(kVK_ANSI_H)),
        .init(label: "I", keyCode: UInt32(kVK_ANSI_I)),
        .init(label: "J", keyCode: UInt32(kVK_ANSI_J)),
        .init(label: "K", keyCode: UInt32(kVK_ANSI_K)),
        .init(label: "L", keyCode: UInt32(kVK_ANSI_L)),
        .init(label: "M", keyCode: UInt32(kVK_ANSI_M)),
        .init(label: "N", keyCode: UInt32(kVK_ANSI_N)),
        .init(label: "O", keyCode: UInt32(kVK_ANSI_O)),
        .init(label: "P", keyCode: UInt32(kVK_ANSI_P)),
        .init(label: "Q", keyCode: UInt32(kVK_ANSI_Q)),
        .init(label: "R", keyCode: UInt32(kVK_ANSI_R)),
        .init(label: "S", keyCode: UInt32(kVK_ANSI_S)),
        .init(label: "T", keyCode: UInt32(kVK_ANSI_T)),
        .init(label: "U", keyCode: UInt32(kVK_ANSI_U)),
        .init(label: "V", keyCode: UInt32(kVK_ANSI_V)),
        .init(label: "W", keyCode: UInt32(kVK_ANSI_W)),
        .init(label: "X", keyCode: UInt32(kVK_ANSI_X)),
        .init(label: "Y", keyCode: UInt32(kVK_ANSI_Y)),
        .init(label: "Z", keyCode: UInt32(kVK_ANSI_Z)),
        .init(label: "0", keyCode: UInt32(kVK_ANSI_0)),
        .init(label: "1", keyCode: UInt32(kVK_ANSI_1)),
        .init(label: "2", keyCode: UInt32(kVK_ANSI_2)),
        .init(label: "3", keyCode: UInt32(kVK_ANSI_3)),
        .init(label: "4", keyCode: UInt32(kVK_ANSI_4)),
        .init(label: "5", keyCode: UInt32(kVK_ANSI_5)),
        .init(label: "6", keyCode: UInt32(kVK_ANSI_6)),
        .init(label: "7", keyCode: UInt32(kVK_ANSI_7)),
        .init(label: "8", keyCode: UInt32(kVK_ANSI_8)),
        .init(label: "9", keyCode: UInt32(kVK_ANSI_9)),
        .init(label: "Space", keyCode: UInt32(kVK_Space)),
        .init(label: "Return", keyCode: UInt32(kVK_Return)),
        .init(label: "Escape", keyCode: UInt32(kVK_Escape))
    ]

    static func label(for keyCode: UInt32) -> String? {
        keyOptions.first { $0.keyCode == keyCode }?.label
    }

    static func nextAvailableProfile(existingProfiles: [ShortcutProfile]) -> ShortcutProfile {
        let candidates: [(UInt32, UInt32)] = [
            (UInt32(kVK_ANSI_F), KeyboardShortcutModifier.control.mask | KeyboardShortcutModifier.shift.mask),
            (UInt32(kVK_ANSI_F), KeyboardShortcutModifier.control.mask | KeyboardShortcutModifier.option.mask),
            (UInt32(kVK_ANSI_F), KeyboardShortcutModifier.control.mask | KeyboardShortcutModifier.command.mask),
            (UInt32(kVK_ANSI_G), KeyboardShortcutModifier.control.mask),
            (UInt32(kVK_ANSI_T), KeyboardShortcutModifier.control.mask),
            (UInt32(kVK_ANSI_Y), KeyboardShortcutModifier.control.mask)
        ]
        let usedKeys = Set(existingProfiles.map { $0.shortcut.storageKey })
        let candidate = candidates.first { keyCode, modifiers in
            !usedKeys.contains(KeyboardShortcut(keyCode: keyCode, modifiers: modifiers).storageKey)
        } ?? (UInt32(kVK_ANSI_G), KeyboardShortcutModifier.control.mask | KeyboardShortcutModifier.shift.mask)

        return ShortcutProfile(
            id: UUID().uuidString,
            name: "New Shortcut",
            keyCode: candidate.0,
            modifiers: candidate.1,
            promptTemplate: PromptSettings.defaultTemplate
        )
    }
}

struct KeyboardShortcutKeyOption: Identifiable, Hashable {
    var label: String
    var keyCode: UInt32

    var id: UInt32 { keyCode }
}

enum KeyboardShortcutModifier: String, CaseIterable, Identifiable {
    case control
    case shift
    case option
    case command

    var id: String { rawValue }

    var label: String {
        switch self {
        case .control:
            return "Control"
        case .shift:
            return "Shift"
        case .option:
            return "Option"
        case .command:
            return "Command"
        }
    }

    var mask: UInt32 {
        switch self {
        case .control:
            return UInt32(controlKey)
        case .shift:
            return UInt32(shiftKey)
        case .option:
            return UInt32(optionKey)
        case .command:
            return UInt32(cmdKey)
        }
    }

    static var allMask: UInt32 {
        allCases.reduce(0) { $0 | $1.mask }
    }
}
