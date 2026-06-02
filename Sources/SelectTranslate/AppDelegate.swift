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
    private var accessibilityRetryTask: Task<Void, Never>?
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
        accessibilityRetryTask?.cancel()
        hotKeyManager?.unregister()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "SelectTranslate", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(makeMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide SelectTranslate", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(makeMenuItem(title: "Quit SelectTranslate", action: #selector(quit), keyEquivalent: "q"))
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
        item.button?.title = "Select"
        item.button?.toolTip = "SelectTranslate"

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

    private func startTranslation(
        cancelPendingAccessibilityRetry: Bool = true,
        preferredProcessIdentifier: pid_t? = nil,
        isAccessibilityRetry: Bool = false
    ) {
        if cancelPendingAccessibilityRetry {
            cancelAccessibilityRetry()
        }

        let processIdentifier = preferredProcessIdentifier ?? frontmostExternalProcessIdentifier()
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
            await self.translateCurrentSelection(
                preferredProcessIdentifier: processIdentifier,
                isAccessibilityRetry: isAccessibilityRetry
            )
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

    private func translateCurrentSelection(
        preferredProcessIdentifier: pid_t?,
        isAccessibilityRetry: Bool
    ) async {
        do {
            let sourceText = try await selectionReader.readSelectedText(
                preferredProcessIdentifier: preferredProcessIdentifier
            )
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
            scheduleAccessibilityRetryAfterGrant(preferredProcessIdentifier: preferredProcessIdentifier)
            panelController.showError(
                source: nil,
                title: "Accessibility Permission Required",
                message: "Allow SelectTranslate in System Settings > Privacy & Security > Accessibility. The translation will retry automatically after permission is enabled."
            )
        } catch SelectionReaderError.noSelectedText {
            currentTranslationRequest = nil
            currentTranslationResult = nil
            if isAccessibilityRetry {
                panelController.showError(
                    source: nil,
                    title: "Selected Text Unavailable",
                    message: "Accessibility permission is enabled, but the original selection is no longer available. Return to the app, select text, and press Control + F again."
                )
            } else {
                panelController.showError(
                    source: nil,
                    title: "No Selected Text",
                    message: "Select text before pressing Control + F. Some apps do not expose selected text through Accessibility."
                )
            }
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

    private func scheduleAccessibilityRetryAfterGrant(preferredProcessIdentifier: pid_t?) {
        accessibilityRetryTask?.cancel()
        accessibilityRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }

                let isTrusted = await MainActor.run { [weak self] in
                    self?.selectionReader.isAccessibilityTrusted == true
                }

                guard isTrusted else { continue }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.accessibilityRetryTask = nil
                    self.startTranslation(
                        cancelPendingAccessibilityRetry: false,
                        preferredProcessIdentifier: preferredProcessIdentifier,
                        isAccessibilityRetry: true
                    )
                }
                return
            }
        }
    }

    private func cancelAccessibilityRetry() {
        accessibilityRetryTask?.cancel()
        accessibilityRetryTask = nil
    }

    private func frontmostExternalProcessIdentifier() -> pid_t? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        return application.processIdentifier
    }

    private func translate(request: TranslationRequest, effort: ReasoningEffort, provider: TranslationProvider) async {
        do {
            currentTranslationResult = nil
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
        if provider == .plamo, !PlamoSetupService.isSetupComplete {
            TranslationPreferences.translationProvider = .codex
            panelController.setTranslationProvider(.codex)
            panelController.showError(
                source: currentTranslationRequest?.sourceText,
                title: "PLaMo Not Ready",
                message: "Prepare PLaMo in Settings before selecting it."
            )
            return
        }

        guard let request = currentTranslationRequest else { return }
        await translate(request: request, effort: panelController.reasoningEffort, provider: provider)
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
