import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window

        if !window.isVisible {
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let model = SettingsModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Codex Translator Settings"
        window.minSize = NSSize(width: 640, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SettingsView(model: model) { [weak window] in
                window?.close()
            }
        )

        return window
    }
}

@MainActor
private final class SettingsModel: ObservableObject {
    private var providerObserver: NSObjectProtocol?

    @Published var promptTemplate: String {
        didSet {
            PromptSettings.template = promptTemplate
        }
    }
    @Published var translationProvider: TranslationProvider
    @Published var isPreparingPlamo: Bool = false
    @Published var plamoStatusMessage: String
    @Published var isPlamoStatusError: Bool = false

    init() {
        promptTemplate = PromptSettings.template
        translationProvider = TranslationPreferences.translationProvider
        plamoStatusMessage = PlamoSetupService.isSetupComplete
            ? "PLaMo is ready."
            : "PLaMo dependencies and model will be installed the first time you select PLaMo."
        providerObserver = NotificationCenter.default.addObserver(
            forName: .translationProviderDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let provider = notification.object as? TranslationProvider else { return }
            Task { @MainActor in
                guard self?.translationProvider != provider else { return }
                self?.translationProvider = provider
            }
        }
    }

    deinit {
        if let providerObserver {
            NotificationCenter.default.removeObserver(providerObserver)
        }
    }

    func reset() {
        PromptSettings.resetTemplate()
        promptTemplate = PromptSettings.defaultTemplate
    }

    func selectProvider(_ provider: TranslationProvider) {
        guard provider != translationProvider else { return }

        switch provider {
        case .codex:
            TranslationPreferences.translationProvider = .codex
            translationProvider = .codex
            isPlamoStatusError = false
            plamoStatusMessage = PlamoSetupService.isSetupComplete
                ? "PLaMo is ready."
                : "PLaMo setup is not installed yet."
        case .plamo:
            preparePlamoAndSelect()
        }
    }

    func preparePlamoAndSelect() {
        guard !isPreparingPlamo else { return }

        isPreparingPlamo = true
        isPlamoStatusError = false
        plamoStatusMessage = "Preparing PLaMo."

        Task { [weak self] in
            guard let self else { return }
            do {
                try await PlamoSetupService.prepare { message in
                    Task { @MainActor [weak self] in
                        self?.plamoStatusMessage = message
                    }
                }

                await MainActor.run {
                    self.isPreparingPlamo = false
                    self.isPlamoStatusError = false
                    self.plamoStatusMessage = "PLaMo is ready."
                    TranslationPreferences.translationProvider = .plamo
                    self.translationProvider = .plamo
                }
            } catch {
                await MainActor.run {
                    self.isPreparingPlamo = false
                    self.isPlamoStatusError = true
                    self.plamoStatusMessage = error.localizedDescription
                    self.translationProvider = TranslationPreferences.translationProvider
                }
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(PromptSettings.instructionToken) and \(PromptSettings.textToken)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reset") {
                    model.reset()
                }
                .help("Restore the default prompt")

                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }

            modelSection

            Divider()

            TextEditor(text: $model.promptTemplate)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Model")
                    .font(.system(size: 14, weight: .semibold))

                Picker("", selection: Binding(
                    get: { model.translationProvider },
                    set: { model.selectProvider($0) }
                )) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .disabled(model.isPreparingPlamo)

                if model.isPreparingPlamo {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Prepare PLaMo") {
                    model.preparePlamoAndSelect()
                }
                .disabled(model.isPreparingPlamo || PlamoSetupService.isSetupComplete)
            }

            Text(model.plamoStatusMessage)
                .font(.system(size: 12))
                .foregroundStyle(model.isPlamoStatusError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
