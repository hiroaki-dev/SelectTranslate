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
        NSApp.setActivationPolicy(.regular)
        panelController.onReasoningEffortChanged = { [weak self] effort in
            self?.startSourceRetranslation(effort: effort, provider: .codex)
        }
        panelController.onTranslationProviderChanged = { [weak self] provider in
            self?.startProviderChange(provider)
        }
        panelController.onBackTranslateRequested = { [weak self] in
            self?.startBackTranslation()
        }
        configureApplicationMenu()
        configureStatusItem()
        registerHotKey()
        panelController.showReady(isAccessibilityTrusted: selectionReader.isAccessibilityTrusted)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "CodexTranslator", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(makeMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide CodexTranslator", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(makeMenuItem(title: "Quit CodexTranslator", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let actionsMenuItem = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        let actionsMenu = NSMenu(title: "Actions")
        actionsMenu.addItem(makeMenuItem(title: "Translate Selection", action: #selector(translateSelectionFromMenu)))
        actionsMenu.addItem(makeMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings)))
        actionsMenuItem.submenu = actionsMenu
        mainMenu.addItem(actionsMenuItem)

        NSApp.mainMenu = mainMenu
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
        selectionReader.requestAccessibilityPermissionPromptIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startTranslation() {
        panelController.activateOnNextShow()

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

    private func startSourceRetranslation(effort: ReasoningEffort, provider: TranslationProvider) {
        guard let request = currentTranslationRequest else { return }
        guard translationTask == nil else { return }

        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            await self.translate(request: request, effort: effort, provider: provider)
        }
    }

    private func startProviderChange(_ provider: TranslationProvider) {
        guard translationTask == nil else { return }

        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            await self.applyProviderChange(provider)
        }
    }

    private func startBackTranslation() {
        guard let result = currentTranslationResult else { return }
        guard translationTask == nil else { return }

        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            await self.backTranslate(
                result: result,
                effort: self.panelController.reasoningEffort,
                provider: self.panelController.translationProvider
            )
        }
    }

    private func translateCurrentSelection() async {
        do {
            let sourceText = try await selectionReader.readSelectedText()
            let direction = TranslationDirection.detect(sourceText)
            let request = TranslationRequest(sourceText: sourceText, direction: direction)
            currentTranslationRequest = request

            await translate(
                request: request,
                effort: panelController.reasoningEffort,
                provider: panelController.translationProvider
            )
        } catch SelectionReaderError.accessibilityPermissionRequired {
            currentTranslationRequest = nil
            currentTranslationResult = nil
            requestAccessibilityPermissionFromShortcutIfNeeded()
            panelController.showError(
                source: nil,
                title: "Accessibility Permission Required",
                message: "Allow CodexTranslator in System Settings > Privacy & Security > Accessibility, then press Control + F again."
            )
        } catch SelectionReaderError.noSelectedText {
            currentTranslationRequest = nil
            currentTranslationResult = nil
            panelController.showError(
                source: nil,
                title: "No Selected Text",
                message: "Select text before pressing Control + F. Some apps do not expose selected text through Accessibility."
            )
        } catch {
            panelController.showError(
                source: nil,
                title: "Translation Failed",
                message: error.localizedDescription
            )
        }
    }

    private func requestAccessibilityPermissionFromShortcutIfNeeded() {
        guard !selectionReader.isAccessibilityTrusted else {
            return
        }

        selectionReader.requestAccessibilityPermissionPromptIfNeeded()
    }

    private func translate(request: TranslationRequest, effort: ReasoningEffort, provider: TranslationProvider) async {
        do {
            currentTranslationResult = nil
            if provider == .plamo {
                try await preparePlamoIfNeeded()
            }
            panelController.showLoading(source: request.sourceText, direction: request.direction, provider: provider)
            let translatedText = try await translator.translate(
                request.sourceText,
                direction: request.direction,
                effort: effort,
                provider: provider
            )
            currentTranslationResult = TranslationResult(
                sourceText: request.sourceText,
                direction: request.direction,
                translatedText: translatedText
            )
            panelController.showResult(
                source: request.sourceText,
                translation: translatedText,
                direction: request.direction,
                provider: provider
            )
        } catch {
            panelController.showError(
                source: request.sourceText,
                title: "Translation Failed",
                message: error.localizedDescription
            )
        }
    }

    private func backTranslate(result: TranslationResult, effort: ReasoningEffort, provider: TranslationProvider) async {
        do {
            if provider == .plamo {
                try await preparePlamoIfNeeded()
            }
            panelController.showBackTranslationLoading()
            let backTranslatedText = try await translator.translate(
                result.translatedText,
                direction: result.direction.reversed,
                effort: effort,
                provider: provider
            )
            panelController.showBackTranslationResult(backTranslatedText)
        } catch {
            panelController.showBackTranslationError(error.localizedDescription)
        }
    }

    private func applyProviderChange(_ provider: TranslationProvider) async {
        if provider == .plamo {
            do {
                try await preparePlamoIfNeeded()
            } catch {
                TranslationPreferences.translationProvider = .codex
                panelController.setTranslationProvider(.codex)
                panelController.showError(
                    source: currentTranslationRequest?.sourceText,
                    title: "PLaMo Setup Failed",
                    message: error.localizedDescription
                )
                return
            }
        }

        guard let request = currentTranslationRequest else { return }
        await translate(request: request, effort: panelController.reasoningEffort, provider: provider)
    }

    private func preparePlamoIfNeeded() async throws {
        guard !PlamoSetupService.isSetupComplete else { return }

        let progressLog = SetupProgressLog()
        let initialLog = await progressLog.append("Installing dependencies and downloading the model.")
        panelController.showPreparationLoading(
            title: "Preparing PLaMo",
            message: initialLog
        )

        try await PlamoSetupService.prepare { [weak self, progressLog] message in
            Task { @MainActor [weak self] in
                let displayText = await progressLog.append(message)
                self?.panelController.showPreparationLoading(title: "Preparing PLaMo", message: displayText)
            }
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

private actor SetupProgressLog {
    private var lines: [String] = []

    func append(_ message: String) -> String {
        let cleanLines = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in cleanLines where lines.last != line {
            lines.append(line)
        }

        if lines.count > 80 {
            lines.removeFirst(lines.count - 80)
        }

        return lines.joined(separator: "\n")
    }
}
