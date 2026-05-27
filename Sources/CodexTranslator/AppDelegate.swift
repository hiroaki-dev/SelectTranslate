import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let selectionReader = SelectionReader()
    private let translator = CodexTranslationService()
    private let panelController = TranslationPanelController()

    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var translationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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

    private func translateCurrentSelection() async {
        do {
            let sourceText = try await selectionReader.readSelectedText()
            let direction = TranslationDirection.detect(sourceText)
            panelController.showLoading(source: sourceText, direction: direction)

            let translatedText = try await translator.translate(sourceText, direction: direction)
            panelController.showResult(source: sourceText, translation: translatedText, direction: direction)
        } catch SelectionReaderError.accessibilityPermissionRequired {
            panelController.showError(
                source: nil,
                title: "Accessibility Permission Required",
                message: "Allow this process in System Settings > Privacy & Security > Accessibility, then press Control + F again."
            )
            selectionReader.requestAccessibilityPermission()
        } catch SelectionReaderError.noSelectedText {
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
}
