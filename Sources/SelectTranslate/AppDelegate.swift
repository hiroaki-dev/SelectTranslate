import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let selectionReader = SelectionReader()
    private let translator = CodexTranslationService()
    private let panelController = TranslationPanelController()
    private let settingsWindowController = SettingsWindowController()

    private var hotKeyManagers: [HotKeyManager] = []
    private var shortcutProfilesObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var translationTask: Task<Void, Never>?
    private var accessibilityRetryTask: Task<Void, Never>?
    private var currentTranslationRequest: TranslationRequest?
    private var currentTranslationResult: TranslationResult?
    private var translationCache: [TranslationCacheKey: String] = [:]

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
        panelController.onSourceTranslateRequested = { [weak self] in
            self?.startManualSourceTranslation()
        }
        configureApplicationMenu()
        configureStatusItem()
        observeShortcutProfileChanges()
        registerHotKeys()
        let isAccessibilityTrusted = selectionReader.requestAccessibilityPermissionPromptIfNeeded()
        panelController.showReady(isAccessibilityTrusted: isAccessibilityTrusted)
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityRetryTask?.cancel()
        unregisterHotKeys()
        if let shortcutProfilesObserver {
            NotificationCenter.default.removeObserver(shortcutProfilesObserver)
        }
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

    private func observeShortcutProfileChanges() {
        shortcutProfilesObserver = NotificationCenter.default.addObserver(
            forName: .shortcutProfilesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.registerHotKeys()
            }
        }
    }

    private func registerHotKeys() {
        unregisterHotKeys()

        let profiles = PromptSettings.shortcutProfiles
        var registrationErrors: [String] = []

        for (index, profile) in profiles.enumerated() {
            let manager = HotKeyManager(
                id: UInt32(index + 1),
                keyCode: profile.keyCode,
                modifiers: profile.modifiers
            ) { [weak self, profileID = profile.id] in
                Task { @MainActor in
                    let latestProfile = PromptSettings.profile(withID: profileID) ?? profile
                    self?.startTranslation(shortcutProfile: latestProfile)
                }
            }

            do {
                try manager.register()
                hotKeyManagers.append(manager)
            } catch {
                registrationErrors.append("\(profile.displayName) (\(profile.shortcutLabel)): \(error.localizedDescription)")
            }
        }

        if !registrationErrors.isEmpty {
            panelController.showError(
                source: nil,
                title: "Shortcut Error",
                message: registrationErrors.joined(separator: "\n")
            )
        }
    }

    private func unregisterHotKeys() {
        hotKeyManagers.forEach { $0.unregister() }
        hotKeyManagers.removeAll()
    }

    @objc private func translateSelectionFromMenu() {
        startTranslation(shortcutProfile: PromptSettings.defaultShortcutProfile)
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
        shortcutProfile: ShortcutProfile,
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
                isAccessibilityRetry: isAccessibilityRetry,
                shortcutProfile: shortcutProfile
            )
        }
    }

    private func startSourceRetranslation(effort: ReasoningEffort, provider: TranslationProvider) {
        guard let request = makeTranslationRequest(from: panelController.sourceText) else { return }
        guard translationTask == nil else { return }

        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            await self.translatePreparedRequest(request, effort: effort, provider: provider)
        }
    }

    private func startManualSourceTranslation() {
        cancelAccessibilityRetry()
        let sourceText = panelController.sourceText
        guard let request = makeTranslationRequest(from: sourceText) else {
            panelController.showError(
                source: sourceText,
                title: "No Original Text",
                message: "Type or paste text in Original before translating."
            )
            return
        }

        panelController.activateOnNextShow()

        guard translationTask == nil else {
            panelController.showError(
                source: sourceText,
                title: "Translation Running",
                message: "The current translation is still running."
            )
            return
        }

        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            await self.translatePreparedRequest(
                request,
                effort: self.panelController.reasoningEffort,
                provider: self.panelController.translationProvider
            )
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
        isAccessibilityRetry: Bool,
        shortcutProfile: ShortcutProfile
    ) async {
        do {
            let sourceText = try await selectionReader.readSelectedText(
                preferredProcessIdentifier: preferredProcessIdentifier
            )
            let request = TranslationRequest(
                sourceText: sourceText,
                direction: TranslationDirection.detect(sourceText),
                shortcutProfile: shortcutProfile
            )
            updateCurrentTranslationRequest(request)

            await translate(
                request: request,
                effort: panelController.reasoningEffort,
                provider: panelController.translationProvider
            )
        } catch SelectionReaderError.accessibilityPermissionRequired {
            currentTranslationRequest = nil
            currentTranslationResult = nil
            requestAccessibilityPermissionFromShortcutIfNeeded()
            scheduleAccessibilityRetryAfterGrant(
                preferredProcessIdentifier: preferredProcessIdentifier,
                shortcutProfile: shortcutProfile
            )
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
                    message: "Accessibility permission is enabled, but the original selection is no longer available. Return to the app, select text, and press \(shortcutProfile.shortcutLabel) again."
                )
            } else {
                panelController.showError(
                    source: nil,
                    title: "No Selected Text",
                    message: "Select text before pressing \(shortcutProfile.shortcutLabel). Some apps do not expose selected text through Accessibility."
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

    private func scheduleAccessibilityRetryAfterGrant(preferredProcessIdentifier: pid_t?, shortcutProfile: ShortcutProfile) {
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
                        shortcutProfile: shortcutProfile,
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

    private func makeTranslationRequest(from sourceText: String) -> TranslationRequest? {
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let shortcutProfile = activeShortcutProfile()
        return TranslationRequest(
            sourceText: sourceText,
            direction: TranslationDirection.detect(sourceText),
            shortcutProfile: shortcutProfile
        )
    }

    private func activeShortcutProfile() -> ShortcutProfile {
        guard let shortcutProfile = currentTranslationRequest?.shortcutProfile else {
            return PromptSettings.defaultShortcutProfile
        }

        return PromptSettings.profile(withID: shortcutProfile.id) ?? shortcutProfile
    }

    private func updateCurrentTranslationRequest(_ request: TranslationRequest) {
        if currentTranslationRequest?.sourceText != request.sourceText {
            translationCache.removeAll()
            currentTranslationResult = nil
        }
        currentTranslationRequest = request
    }

    private func translatePreparedRequest(
        _ request: TranslationRequest,
        effort: ReasoningEffort,
        provider: TranslationProvider
    ) async {
        updateCurrentTranslationRequest(request)
        if showCachedTranslationIfAvailable(request: request, effort: effort, provider: provider) {
            return
        }

        await translate(request: request, effort: effort, provider: provider)
    }

    private func translate(request: TranslationRequest, effort: ReasoningEffort, provider: TranslationProvider) async {
        do {
            let cacheKey = TranslationCacheKey(request: request, effort: effort, provider: provider)
            currentTranslationResult = nil
            panelController.showLoading(
                source: request.sourceText,
                direction: request.direction,
                provider: provider,
                shortcutProfile: request.shortcutProfile
            )
            let translatedText = try await translator.translate(
                request.sourceText,
                direction: request.direction,
                effort: effort,
                provider: provider,
                promptTemplate: request.shortcutProfile.normalizedPromptTemplate
            )
            translationCache[cacheKey] = translatedText
            currentTranslationResult = TranslationResult(
                sourceText: request.sourceText,
                direction: request.direction,
                translatedText: translatedText,
                shortcutProfile: request.shortcutProfile
            )
            panelController.showResult(
                source: request.sourceText,
                translation: translatedText,
                direction: request.direction,
                provider: provider,
                shortcutProfile: request.shortcutProfile
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
        if showCachedBackTranslationIfAvailable(result: result, effort: effort, provider: provider) {
            return
        }

        do {
            let cacheKey = TranslationCacheKey.backTranslation(result: result, effort: effort, provider: provider)
            panelController.showBackTranslationLoading()
            let backTranslatedText = try await translator.translate(
                result.translatedText,
                direction: result.direction.reversed,
                effort: effort,
                provider: provider,
                promptTemplate: result.shortcutProfile.normalizedPromptTemplate
            )
            translationCache[cacheKey] = backTranslatedText
            panelController.showBackTranslationResult(backTranslatedText)
        } catch {
            panelController.showBackTranslationError(error.localizedDescription)
        }
    }

    private func showCachedTranslationIfAvailable(
        request: TranslationRequest,
        effort: ReasoningEffort,
        provider: TranslationProvider
    ) -> Bool {
        let cacheKey = TranslationCacheKey(request: request, effort: effort, provider: provider)
        guard let translatedText = translationCache[cacheKey] else {
            return false
        }

        let result = TranslationResult(
            sourceText: request.sourceText,
            direction: request.direction,
            translatedText: translatedText,
            shortcutProfile: request.shortcutProfile
        )
        currentTranslationResult = result
        panelController.showResult(
            source: request.sourceText,
            translation: translatedText,
            direction: request.direction,
            provider: provider,
            shortcutProfile: request.shortcutProfile
        )
        _ = showCachedBackTranslationIfAvailable(result: result, effort: effort, provider: provider)
        return true
    }

    private func showCachedBackTranslationIfAvailable(
        result: TranslationResult,
        effort: ReasoningEffort,
        provider: TranslationProvider
    ) -> Bool {
        let cacheKey = TranslationCacheKey.backTranslation(result: result, effort: effort, provider: provider)
        guard let backTranslatedText = translationCache[cacheKey] else {
            return false
        }

        panelController.showBackTranslationResult(backTranslatedText)
        return true
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

        guard let request = makeTranslationRequest(from: panelController.sourceText) else { return }
        let effort = panelController.reasoningEffort
        await translatePreparedRequest(request, effort: effort, provider: provider)
    }
}

private struct TranslationRequest {
    let sourceText: String
    let direction: TranslationDirection
    let shortcutProfile: ShortcutProfile
}

private struct TranslationResult {
    let sourceText: String
    let direction: TranslationDirection
    let translatedText: String
    let shortcutProfile: ShortcutProfile
}

private struct TranslationCacheKey: Hashable {
    let sourceText: String
    let direction: TranslationDirection
    let provider: TranslationProvider
    let effort: ReasoningEffort
    let shortcutProfileID: String
    let promptTemplate: String
    let apiBaseURL: String
    let apiModel: String

    init(request: TranslationRequest, effort: ReasoningEffort, provider: TranslationProvider) {
        self.init(
            sourceText: request.sourceText,
            direction: request.direction,
            shortcutProfile: request.shortcutProfile,
            effort: effort,
            provider: provider
        )
    }

    static func backTranslation(
        result: TranslationResult,
        effort: ReasoningEffort,
        provider: TranslationProvider
    ) -> TranslationCacheKey {
        TranslationCacheKey(
            sourceText: result.translatedText,
            direction: result.direction.reversed,
            shortcutProfile: result.shortcutProfile,
            effort: effort,
            provider: provider
        )
    }

    private init(
        sourceText: String,
        direction: TranslationDirection,
        shortcutProfile: ShortcutProfile,
        effort: ReasoningEffort,
        provider: TranslationProvider
    ) {
        self.sourceText = sourceText
        self.direction = direction
        self.provider = provider
        self.effort = provider == .codex ? effort : .low
        shortcutProfileID = shortcutProfile.id
        promptTemplate = provider == .plamo ? "" : shortcutProfile.normalizedPromptTemplate

        if provider == .openAICompatible {
            apiBaseURL = OpenAICompatibleSettings.baseURL
            apiModel = OpenAICompatibleSettings.model
        } else {
            apiBaseURL = ""
            apiModel = ""
        }
    }
}
