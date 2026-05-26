import AppKit
import ApplicationServices
import Carbon

enum SelectionReaderError: LocalizedError {
    case accessibilityPermissionRequired
    case noSelectedText

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required to read the selected text."
        case .noSelectedText:
            return "No selected text was copied from the frontmost app."
        }
    }
}

@MainActor
final class SelectionReader {
    private let pasteboard = NSPasteboard.general

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func readSelectedText() async throws -> String {
        guard isAccessibilityTrusted else {
            throw SelectionReaderError.accessibilityPermissionRequired
        }

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        let clearChangeCount = pasteboard.changeCount

        postCopyShortcut()

        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if pasteboard.changeCount != clearChangeCount {
                break
            }
        }

        let copiedText = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        snapshot.restore(to: pasteboard)

        guard let copiedText, !copiedText.isEmpty else {
            throw SelectionReaderError.noSelectedText
        }

        return copiedText
    }

    private func postCopyShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)

        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand

        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let copiedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copiedItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copiedItem.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    copiedItem.setString(string, forType: type)
                }
            }
            return copiedItem
        } ?? []

        return PasteboardSnapshot(items: copiedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
