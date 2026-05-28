import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let selectionReader = SelectionReader()
    private let translator = CodexTranslationService()
    private let panelController = TranslationPanelController()
    private let settingsWindowController = SettingsWindowController()

    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var translationTask: Task<Void, Never>?
    private var currentTranslationRequest: TranslationRequest?
    private var currentTranslationResult: TranslationResult?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController.onReasoningEffortChanged = { [weak self] effort in
            self?.startSourceRetranslation(effort: effort)
        }
        panelController.onBackTranslateRequested = { [weak self] in
            self?.startBackTranslation()
        }
        configureStatusItem()
        registerHotKey()
        panelController.showReady(isAccessibilityTrusted: selectionReader.isAccessibilityTrusted)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Codex"
        item.button?.toolTip = "Codex Translator"

        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "Translate Selection", action: #selector(translateSelectionFromMenu)))
        menu.addItem(makeMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(makeMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings)))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    private func makeMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func registerHotKey() {
        do {
            let manager = HotKeyManager(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey)) { [weak self] in
                Task { @MainActor in
                    self?.startTranslation()
                }
            }
            try manager.register()
            hotKeyManager = manager
        } catch {
            panelController.showError(
                source: nil,
                title: "Shortcut Error",
                message: "Control + F could not be registered: \(error.localizedDescription)"
            )
        }
    }

    @objc private func translateSelectionFromMenu() {
        startTranslation()
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func openAccessibilitySettings() {
        selectionReader.requestAccessibilityPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startTranslation() {
        guard translationTask == nil else {
            panelController.showError(
                source: nil,
                title: "Translation Running",
                message: "The current translation is still running."
            )
            return
        }

        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            await self.translateCurrentSelection()
        }
    }

    private func startSourceRetranslation(effort: ReasoningEffort) {
        guard let request = currentTranslationRequest else { return }
        guard translationTask == nil else { return }

        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            await self.translate(request: request, effort: effort)
        }
    }

    private func startBackTranslation() {
        guard let result = currentTranslationResult else { return }
        guard translationTask == nil else { return }

        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            await self.backTranslate(result: result, effort: self.panelController.reasoningEffort)
        }
    }

    private func translateCurrentSelection() async {
        do {
            let sourceText = try await selectionReader.readSelectedText()
            let direction = TranslationDirection.detect(sourceText)
            let request = TranslationRequest(sourceText: sourceText, direction: direction)
            currentTranslationRequest = request

            await translate(request: request, effort: panelController.reasoningEffort)
        } catch SelectionReaderError.accessibilityPermissionRequired {
            currentTranslationRequest = nil
            currentTranslationResult = nil
            panelController.showError(
                source: nil,
                title: "Accessibility Permission Required",
                message: "Allow this process in System Settings > Privacy & Security > Accessibility, then press Control + F again."
            )
            selectionReader.requestAccessibilityPermission()
        } catch SelectionReaderError.noSelectedText {
            currentTranslationRequest = nil
            currentTranslationResult = nil
            panelController.showError(
                source: nil,
                title: "No Selected Text",
                message: "Select text in the frontmost app before pressing Control + F."
            )
        } catch {
            panelController.showError(
                source: nil,
                title: "Translation Failed",
                message: error.localizedDescription
            )
        }
    }

    private func translate(request: TranslationRequest, effort: ReasoningEffort) async {
        do {
            currentTranslationResult = nil
            panelController.showLoading(source: request.sourceText, direction: request.direction)
            let translatedText = try await translator.translate(
                request.sourceText,
                direction: request.direction,
                effort: effort
            )
            currentTranslationResult = TranslationResult(
                sourceText: request.sourceText,
                direction: request.direction,
                translatedText: translatedText
            )
            panelController.showResult(
                source: request.sourceText,
                translation: translatedText,
                direction: request.direction
            )
        } catch {
            panelController.showError(
                source: request.sourceText,
                title: "Translation Failed",
                message: error.localizedDescription
            )
        }
    }

    private func backTranslate(result: TranslationResult, effort: ReasoningEffort) async {
        do {
            panelController.showBackTranslationLoading()
            let backTranslatedText = try await translator.translate(
                result.translatedText,
                direction: result.direction.reversed,
                effort: effort
            )
            panelController.showBackTranslationResult(backTranslatedText)
        } catch {
            panelController.showBackTranslationError(error.localizedDescription)
        }
    }
}

private struct TranslationRequest {
    let sourceText: String
    let direction: TranslationDirection
}

private struct TranslationResult {
    let sourceText: String
    let direction: TranslationDirection
    let translatedText: String
}
