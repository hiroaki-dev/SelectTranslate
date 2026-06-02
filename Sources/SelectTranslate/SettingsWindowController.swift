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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "SelectTranslate Settings"
        window.minSize = NSSize(width: 700, height: 620)
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
    @Published var apiBaseURL: String {
        didSet {
            OpenAICompatibleSettings.baseURL = apiBaseURL
        }
    }
    @Published var apiKey: String {
        didSet {
            OpenAICompatibleSettings.apiKey = apiKey
        }
    }
    @Published var apiModel: String {
        didSet {
            OpenAICompatibleSettings.model = apiModel
        }
    }
    @Published var isAPIKeyVisible: Bool = false
    @Published var isPlamoReady: Bool
    @Published var isPreparingPlamo: Bool = false
    @Published var plamoStatusMessage: String
    @Published var plamoStatusLog: String = ""
    @Published var isPlamoStatusError: Bool = false
    private var plamoLogLines: [String] = []

    init() {
        promptTemplate = PromptSettings.template
        apiBaseURL = OpenAICompatibleSettings.baseURL
        apiKey = OpenAICompatibleSettings.apiKey
        apiModel = OpenAICompatibleSettings.model
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
        case .openAICompatible:
            TranslationPreferences.translationProvider = .openAICompatible
            translationProvider = .openAICompatible
            isPlamoStatusError = false
            plamoStatusMessage = isPlamoReady
                ? "PLaMo is ready."
                : "PLaMo setup is not installed yet."
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

            if model.translationProvider == .openAICompatible {
                apiSection
            }

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
                    width: 270
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

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI Compatible API")
                        .font(.system(size: 14, weight: .semibold))
                    Text("base_url must include /v1. Uses POST {base_url}/chat/completions.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("base_url")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    TextField("http://localhost:1234/v1", text: $model.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("api_key optional")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)
                    HStack(spacing: 6) {
                        APIKeyField(text: $model.apiKey, isSecure: !model.isAPIKeyVisible)
                            .id(model.isAPIKeyVisible)
                            .frame(height: 22)

                        Button {
                            model.isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: model.isAPIKeyVisible ? "eye.slash" : "eye")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(model.isAPIKeyVisible ? "Hide API key" : "Show API key")
                    }
                }

                GridRow {
                    Text("model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    TextField("Enter the model name", text: $model.apiModel)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

private struct APIKeyField: NSViewRepresentable {
    @Binding var text: String
    let isSecure: Bool

    func makeNSView(context: Context) -> NSTextField {
        let textField = isSecure ? NSSecureTextField() : NSTextField()
        textField.stringValue = text
        textField.delegate = context.coordinator
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.focusRingType = .default
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            text.wrappedValue = textField.stringValue
        }
    }
}
