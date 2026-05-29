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
    private var plamoSetupObserver: NSObjectProtocol?

    @Published var promptTemplate: String {
        didSet {
            PromptSettings.template = promptTemplate
        }
    }
    @Published var translationProvider: TranslationProvider
    @Published var isPlamoReady: Bool
    @Published var isPreparingPlamo: Bool = false
    @Published var plamoStatusMessage: String
    @Published var plamoStatusLog: String = ""
    @Published var isPlamoStatusError: Bool = false
    private var plamoLogLines: [String] = []

    init() {
        promptTemplate = PromptSettings.template
        let plamoReady = PlamoSetupService.isSetupComplete
        isPlamoReady = plamoReady
        translationProvider = TranslationPreferences.translationProvider
        plamoStatusMessage = plamoReady
            ? "PLaMo is ready."
            : "Prepare PLaMo before selecting it."
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
        plamoSetupObserver = NotificationCenter.default.addObserver(
            forName: .plamoSetupStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPlamoReadiness()
            }
        }
    }

    deinit {
        if let providerObserver {
            NotificationCenter.default.removeObserver(providerObserver)
        }
        if let plamoSetupObserver {
            NotificationCenter.default.removeObserver(plamoSetupObserver)
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
            plamoStatusMessage = isPlamoReady
                ? "PLaMo is ready."
                : "PLaMo setup is not installed yet."
        case .plamo:
            guard isPlamoReady else {
                isPlamoStatusError = false
                plamoStatusMessage = "Prepare PLaMo before selecting it."
                translationProvider = .codex
                return
            }
            TranslationPreferences.translationProvider = .plamo
            translationProvider = .plamo
            isPlamoStatusError = false
            plamoStatusMessage = "PLaMo is ready."
        }
    }

    func preparePlamo() {
        guard !isPreparingPlamo else { return }

        isPreparingPlamo = true
        isPlamoStatusError = false
        plamoLogLines = []
        plamoStatusLog = ""
        appendPlamoProgress("Preparing PLaMo.")

        Task { [weak self] in
            guard let self else { return }
            do {
                try await PlamoSetupService.prepare { message in
                    Task { @MainActor [weak self] in
                        self?.appendPlamoProgress(message)
                    }
                }

                await MainActor.run {
                    self.isPreparingPlamo = false
                    self.isPlamoStatusError = false
                    self.isPlamoReady = PlamoSetupService.isSetupComplete
                    self.appendPlamoProgress("PLaMo is ready.")
                }
            } catch {
                await MainActor.run {
                    self.isPreparingPlamo = false
                    self.isPlamoStatusError = true
                    self.isPlamoReady = PlamoSetupService.isSetupComplete
                    self.appendPlamoProgress("ERROR: \(error.localizedDescription)")
                    self.translationProvider = TranslationPreferences.translationProvider
                }
            }
        }
    }

    private func refreshPlamoReadiness() {
        isPlamoReady = PlamoSetupService.isSetupComplete
        if !isPlamoReady, translationProvider == .plamo {
            translationProvider = .codex
            TranslationPreferences.translationProvider = .codex
        }
        if isPlamoReady, !isPreparingPlamo {
            isPlamoStatusError = false
            plamoStatusMessage = "PLaMo is ready."
        }
    }

    private func appendPlamoProgress(_ message: String) {
        let cleanLines = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanLines.isEmpty else { return }
        plamoStatusMessage = cleanLines.last ?? message

        for line in cleanLines {
            if plamoLogLines.last != line {
                plamoLogLines.append(line)
            }
        }

        if plamoLogLines.count > 80 {
            plamoLogLines.removeFirst(plamoLogLines.count - 80)
        }
        plamoStatusLog = plamoLogLines.joined(separator: "\n")
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

                ProviderSegmentedControl(
                    selection: Binding(
                        get: { model.translationProvider },
                        set: { model.selectProvider($0) }
                    ),
                    isPlamoReady: model.isPlamoReady,
                    isDisabled: model.isPreparingPlamo,
                    width: 180
                )

                if model.isPreparingPlamo {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Prepare PLaMo") {
                    model.preparePlamo()
                }
                .disabled(model.isPreparingPlamo || model.isPlamoReady)
            }

            Text(model.plamoStatusMessage)
                .font(.system(size: 12))
                .foregroundStyle(model.isPlamoStatusError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.plamoStatusLog.isEmpty {
                ScrollView {
                    Text(model.plamoStatusLog)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
    }
}
