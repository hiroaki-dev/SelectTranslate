import ApplicationServices
import Foundation

enum SelectionReaderError: LocalizedError {
    case accessibilityPermissionRequired
    case noSelectedText

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required to read the selected text."
        case .noSelectedText:
            return "No selected text is exposed by the frontmost app through Accessibility."
        }
    }
}

@MainActor
final class SelectionReader {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func readSelectedText() async throws -> String {
        guard isAccessibilityTrusted else {
            throw SelectionReaderError.accessibilityPermissionRequired
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedRef = copyAttribute(kAXFocusedUIElementAttribute as CFString, from: systemWideElement),
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            throw SelectionReaderError.noSelectedText
        }
        let focusedElement = focusedRef as! AXUIElement

        if let selectedText = selectedTextAttribute(from: focusedElement) {
            return selectedText
        }

        if let selectedText = selectedTextFromRangeParameter(from: focusedElement) {
            return selectedText
        }

        if let selectedText = selectedTextFromValueRange(from: focusedElement) {
            return selectedText
        }

        throw SelectionReaderError.noSelectedText
    }

    private func selectedTextAttribute(from element: AXUIElement) -> String? {
        guard let text = copyAttribute(kAXSelectedTextAttribute as CFString, from: element) as? String else {
            return nil
        }
        return nonEmpty(text)
    }

    private func selectedTextFromRangeParameter(from element: AXUIElement) -> String? {
        guard let range = selectedRange(from: element) else {
            return nil
        }

        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }

        var textRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &textRef
        )

        guard result == .success, let text = textRef as? String else {
            return nil
        }

        return nonEmpty(text)
    }

    private func selectedTextFromValueRange(from element: AXUIElement) -> String? {
        guard let range = selectedRange(from: element),
              let fullText = copyAttribute(kAXValueAttribute as CFString, from: element) as? String else {
            return nil
        }

        let nsText = fullText as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard nsRange.location >= 0,
              nsRange.length > 0,
              NSMaxRange(nsRange) <= nsText.length else {
            return nil
        }

        return nonEmpty(nsText.substring(with: nsRange))
    }

    private func selectedRange(from element: AXUIElement) -> CFRange? {
        guard let rangeRef = copyAttribute(kAXSelectedTextRangeAttribute as CFString, from: element),
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            return nil
        }

        let rangeValue = rangeRef as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length > 0 else {
            return nil
        }

        return range
    }

    private func copyAttribute(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
