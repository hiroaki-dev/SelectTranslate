import ApplicationServices
import AppKit
import Foundation

enum SelectionReaderError: LocalizedError {
    case accessibilityPermissionRequired
    case chromeAutomationPermissionRequired
    case chromeJavaScriptAppleEventsDisabled
    case noSelectedText

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required to read the selected text."
        case .chromeAutomationPermissionRequired:
            return "Automation permission is required to read selected text from Chrome."
        case .chromeJavaScriptAppleEventsDisabled:
            return "Chrome is blocking JavaScript from Apple Events."
        case .noSelectedText:
            return "No selected text is exposed through Accessibility."
        }
    }
}

@MainActor
final class SelectionReader {
    private let maxSearchDepth = 6
    private let maxVisitedElements = 900
    private let accessibilityTimeout: Float = 0.08

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermissionPromptIfNeeded() -> Bool {
        guard !isAccessibilityTrusted else {
            return true
        }

        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func readSelectedText(preferredProcessIdentifier: pid_t? = nil) async throws -> String {
        guard isAccessibilityTrusted else {
            throw SelectionReaderError.accessibilityPermissionRequired
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        let candidates = candidateElements(
            from: systemWideElement,
            preferredProcessIdentifier: preferredProcessIdentifier
        )
        var visitedElements = Set<CFHashCode>()
        var remainingElements = maxVisitedElements

        for candidate in candidates {
            if let selectedText = selectedText(
                in: candidate,
                maxDepth: maxSearchDepth,
                visitedElements: &visitedElements,
                remainingElements: &remainingElements
            ) {
                return selectedText
            }
        }

        if let browserSelectedText = try chromiumBrowserSelectedText(preferredProcessIdentifier: preferredProcessIdentifier) {
            return browserSelectedText
        }

        throw SelectionReaderError.noSelectedText
    }

    private func candidateElements(
        from systemWideElement: AXUIElement,
        preferredProcessIdentifier: pid_t?
    ) -> [AXUIElement] {
        var candidates: [AXUIElement] = []

        if let preferredProcessIdentifier,
           preferredProcessIdentifier != ProcessInfo.processInfo.processIdentifier {
            let preferredApplication = AXUIElementCreateApplication(preferredProcessIdentifier)
            appendIfExternal(preferredApplication, to: &candidates)
        }

        if let focusedElement = elementAttribute(kAXFocusedUIElementAttribute as CFString, from: systemWideElement) {
            appendIfExternal(focusedElement, to: &candidates)
        }

        if let focusedApplication = elementAttribute(kAXFocusedApplicationAttribute as CFString, from: systemWideElement) {
            appendIfExternal(focusedApplication, to: &candidates)
        }

        if let elementAtMouse = elementAtMousePosition(from: systemWideElement) {
            appendIfExternal(elementAtMouse, to: &candidates)
        }

        for application in runningApplicationElements() {
            appendIfExternal(application, to: &candidates)
        }

        return candidates
    }

    private func selectedText(
        in element: AXUIElement,
        maxDepth: Int,
        visitedElements: inout Set<CFHashCode>,
        remainingElements: inout Int
    ) -> String? {
        guard remainingElements > 0 else {
            return nil
        }

        let elementHash = CFHash(element)
        guard !visitedElements.contains(elementHash) else {
            return nil
        }

        visitedElements.insert(elementHash)
        remainingElements -= 1
        AXUIElementSetMessagingTimeout(element, accessibilityTimeout)

        if let selectedText = selectedTextDirectly(from: element) {
            return selectedText
        }

        guard maxDepth > 0 else {
            return nil
        }

        for child in childElements(from: element) {
            if let selectedText = selectedText(
                in: child,
                maxDepth: maxDepth - 1,
                visitedElements: &visitedElements,
                remainingElements: &remainingElements
            ) {
                return selectedText
            }
        }

        return nil
    }

    private func selectedTextDirectly(from element: AXUIElement) -> String? {
        if let selectedText = selectedTextAttribute(from: element) {
            return selectedText
        }

        if let selectedText = selectedTextFromRangeParameter(from: element) {
            return selectedText
        }

        if let selectedText = selectedTextFromValueRange(from: element) {
            return selectedText
        }

        return nil
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

    private func elementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func runningApplicationElements() -> [AXUIElement] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !application.isTerminated,
                  application.activationPolicy == .regular || application.activationPolicy == .accessory else {
                return nil
            }

            let element = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(element, accessibilityTimeout)
            return element
        }
    }

    private func appendIfExternal(_ element: AXUIElement, to candidates: inout [AXUIElement]) {
        guard !isCurrentProcessElement(element) else {
            return
        }

        let elementHash = CFHash(element)
        guard !candidates.contains(where: { CFHash($0) == elementHash }) else {
            return
        }

        AXUIElementSetMessagingTimeout(element, accessibilityTimeout)
        candidates.append(element)
    }

    private func isCurrentProcessElement(_ element: AXUIElement) -> Bool {
        guard let pid = processIdentifier(for: element) else {
            return false
        }

        return pid == ProcessInfo.processInfo.processIdentifier
    }

    private func processIdentifier(for element: AXUIElement) -> pid_t? {
        var pid = pid_t()
        let result = AXUIElementGetPid(element, &pid)
        guard result == .success else {
            return nil
        }
        return pid
    }

    private func childElements(from element: AXUIElement) -> [AXUIElement] {
        let attributes = [
            kAXFocusedUIElementAttribute,
            kAXFocusedWindowAttribute,
            kAXSelectedChildrenAttribute,
            kAXVisibleChildrenAttribute,
            kAXChildrenAttribute,
            kAXWindowsAttribute
        ].map { $0 as CFString }

        return attributes.flatMap { childElements(for: $0, from: element) }
    }

    private func childElements(for attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(attribute, from: element) else {
            return []
        }

        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [value as! AXUIElement]
        }

        guard CFGetTypeID(value) == CFArrayGetTypeID(),
              let array = value as? [Any] else {
            return []
        }

        return array.compactMap { item in
            guard let item = item as CFTypeRef?,
                  CFGetTypeID(item) == AXUIElementGetTypeID() else {
                return nil
            }
            return (item as! AXUIElement)
        }
    }

    private func elementAtMousePosition(from systemWideElement: AXUIElement) -> AXUIElement? {
        let mouseLocation = NSEvent.mouseLocation
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(mouseLocation.x),
            Float(mouseLocation.y),
            &elementRef
        )

        guard result == .success else {
            return nil
        }

        return elementRef
    }

    private func chromiumBrowserSelectedText(preferredProcessIdentifier: pid_t?) throws -> String? {
        guard let application = browserApplication(preferredProcessIdentifier: preferredProcessIdentifier),
              let bundleIdentifier = application.bundleIdentifier,
              Self.chromeBundleIdentifiers.contains(bundleIdentifier) else {
            return nil
        }

        let script = """
        tell application id "\(bundleIdentifier)"
            if not (exists front window) then return ""
            tell active tab of front window
                return execute javascript "\(Self.appleScriptEscaped(Self.chromeSelectionJavaScript))"
            end tell
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }

        let result = appleScript.executeAndReturnError(&error)
        if let error {
            if Self.isChromeJavaScriptAppleEventsDisabled(error) {
                throw SelectionReaderError.chromeJavaScriptAppleEventsDisabled
            }

            if Self.isAutomationPermissionError(error) {
                throw SelectionReaderError.chromeAutomationPermissionRequired
            }

            return nil
        }

        return nonEmpty(result.stringValue ?? "")
    }

    private func browserApplication(preferredProcessIdentifier: pid_t?) -> NSRunningApplication? {
        if let preferredProcessIdentifier,
           let application = NSWorkspace.shared.runningApplications.first(where: {
               $0.processIdentifier == preferredProcessIdentifier
           }) {
            return application
        }

        return NSWorkspace.shared.frontmostApplication
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let chromeBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev"
    ]

    private static let chromeSelectionJavaScript = [
        #"(() => {"#,
        #"const selection = window.getSelection ? window.getSelection().toString() : "";"#,
        #"if (selection) return selection;"#,
        #"const element = document.activeElement;"#,
        #"if (!element || typeof element.value !== "string") return "";"#,
        #"const start = element.selectionStart;"#,
        #"const end = element.selectionEnd;"#,
        #"if (typeof start !== "number" || typeof end !== "number" || end <= start) return "";"#,
        #"return element.value.substring(start, end);"#,
        #"})()"#
    ].joined(separator: " ")

    private static func appleScriptEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func isChromeJavaScriptAppleEventsDisabled(_ error: NSDictionary) -> Bool {
        let message = appleScriptErrorMessage(error)
        return message.localizedCaseInsensitiveContains("JavaScript through AppleScript")
            || message.localizedCaseInsensitiveContains("Allow JavaScript from Apple Events")
    }

    private static func isAutomationPermissionError(_ error: NSDictionary) -> Bool {
        if appleScriptErrorNumber(error) == -1743 {
            return true
        }

        let message = appleScriptErrorMessage(error)
        return message.localizedCaseInsensitiveContains("Not authorized to send Apple events")
    }

    private static func appleScriptErrorMessage(_ error: NSDictionary) -> String {
        error["NSAppleScriptErrorMessage"] as? String ?? ""
    }

    private static func appleScriptErrorNumber(_ error: NSDictionary) -> Int? {
        if let number = error["NSAppleScriptErrorNumber"] as? NSNumber {
            return number.intValue
        }

        return error["NSAppleScriptErrorNumber"] as? Int
    }
}
