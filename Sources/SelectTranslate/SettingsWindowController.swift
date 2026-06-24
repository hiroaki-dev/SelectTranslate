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
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 820),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "SelectTranslate Settings"
        window.minSize = NSSize(width: 760, height: 680)
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

    @Published private(set) var shortcutProfiles: [ShortcutProfile]
    @Published var selectedShortcutID: String
    @Published var shortcutValidationMessage: String = ""
    @Published var translationProvider: TranslationProvider
    @Published var codexModel: String {
        didSet {
            CodexSettings.model = codexModel
        }
    }
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
    @Published var claudeModel: String {
        didSet {
            ClaudeSettings.model = claudeModel
        }
    }
    @Published var replyPromptTemplate: String {
        didSet {
            PromptSettings.replyTemplate = replyPromptTemplate
        }
    }
    @Published var isAPIKeyVisible: Bool = false
    @Published var isPlamoReady: Bool
    @Published var isPreparingPlamo: Bool = false
    @Published var plamoStatusMessage: String
    @Published var plamoStatusLog: String = ""
    @Published var isPlamoStatusError: Bool = false
    private var plamoLogLines: [String] = []

    var selectedShortcutProfile: ShortcutProfile? {
        shortcutProfiles.first { $0.id == selectedShortcutID }
    }

    var canDeleteSelectedShortcut: Bool {
        shortcutProfiles.count > 1 && selectedShortcutProfile != nil
    }

    init() {
        let loadedProfiles = PromptSettings.shortcutProfiles
        shortcutProfiles = loadedProfiles
        selectedShortcutID = loadedProfiles.first?.id ?? ShortcutProfile.defaultProfile().id
        codexModel = CodexSettings.model
        apiBaseURL = OpenAICompatibleSettings.baseURL
        apiKey = OpenAICompatibleSettings.apiKey
        apiModel = OpenAICompatibleSettings.model
        claudeModel = ClaudeSettings.model
        replyPromptTemplate = PromptSettings.replyTemplate
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

    func selectShortcut(_ id: String) {
        selectedShortcutID = id
    }

    func addShortcut() {
        let profile = KeyboardShortcut.nextAvailableProfile(existingProfiles: shortcutProfiles)
        var profiles = shortcutProfiles
        profiles.append(profile)
        shortcutProfiles = profiles
        selectedShortcutID = profile.id
        persistShortcutProfilesIfValid()
    }

    func deleteSelectedShortcut() {
        guard canDeleteSelectedShortcut else { return }
        var profiles = shortcutProfiles
        profiles.removeAll { $0.id == selectedShortcutID }
        shortcutProfiles = profiles
        selectedShortcutID = shortcutProfiles.first?.id ?? ""
        persistShortcutProfilesIfValid()
    }

    func resetSelectedPrompt() {
        updateSelectedShortcut { profile in
            profile.promptTemplate = PromptSettings.defaultTemplate
        }
    }

    func resetReplyPrompt() {
        PromptSettings.resetReplyTemplate()
        replyPromptTemplate = PromptSettings.replyTemplate
    }

    func updateSelectedShortcutName(_ name: String) {
        updateSelectedShortcut { profile in
            profile.name = name
        }
    }

    func updateSelectedShortcutKeyCode(_ keyCode: UInt32) {
        updateSelectedShortcut { profile in
            profile.keyCode = keyCode
        }
    }

    func setSelectedModifier(_ modifier: KeyboardShortcutModifier, enabled: Bool) {
        updateSelectedShortcut { profile in
            if enabled {
                profile.modifiers |= modifier.mask
            } else {
                profile.modifiers &= ~modifier.mask
            }
        }
    }

    func isSelectedModifierEnabled(_ modifier: KeyboardShortcutModifier) -> Bool {
        guard let profile = selectedShortcutProfile else { return false }
        return profile.shortcut.normalizedModifiers & modifier.mask != 0
    }

    func updateSelectedShortcutPrompt(_ prompt: String) {
        updateSelectedShortcut { profile in
            profile.promptTemplate = prompt
        }
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
        case .claude:
            TranslationPreferences.translationProvider = .claude
            translationProvider = .claude
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

    private func updateSelectedShortcut(_ update: (inout ShortcutProfile) -> Void) {
        var profiles = shortcutProfiles
        guard let index = profiles.firstIndex(where: { $0.id == selectedShortcutID }) else { return }
        update(&profiles[index])
        shortcutProfiles = profiles
        persistShortcutProfilesIfValid()
    }

    private func persistShortcutProfilesIfValid() {
        let messages = PromptSettings.validationMessages(for: shortcutProfiles)
        if messages.isEmpty {
            shortcutValidationMessage = ""
            PromptSettings.saveShortcutProfiles(shortcutProfiles)
        } else {
            shortcutValidationMessage = "\(messages.joined(separator: "\n"))\nChanges are not saved until shortcut conflicts are fixed."
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

private enum SettingsSection: String, CaseIterable, Identifiable {
    case model
    case prompts
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model:
            return "Model"
        case .prompts:
            return "Prompts"
        case .shortcuts:
            return "Shortcuts"
        }
    }

    var subtitle: String {
        switch self {
        case .model:
            return "Choose translation engines and provider-specific settings."
        case .prompts:
            return "Review and edit shared prompt templates."
        case .shortcuts:
            return "Create shortcut sets with separate prompt templates."
        }
    }

    var iconName: String {
        switch self {
        case .model:
            return "cpu"
        case .prompts:
            return "text.quote"
        case .shortcuts:
            return "keyboard"
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var selectedSection: SettingsSection = .model
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                sidebar
                Divider()
                detail
            }
        }
        .frame(minWidth: 760, minHeight: 680)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                Text("Configure translation engines and shortcut-specific prompts.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done", action: close)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.iconName)
                            .frame(width: 18, height: 18)
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedSection == section ? Color.accentColor.opacity(0.18) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 180)
        .frame(maxHeight: .infinity)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader

            switch selectedSection {
            case .model:
                modelSettings
            case .prompts:
                promptsSettings
            case .shortcuts:
                shortcutsSettings
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedSection.title)
                .font(.system(size: 18, weight: .semibold))
            Text(selectedSection.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                modelSection

                if model.translationProvider == .codex {
                    Divider()
                    codexSection
                }

                if model.translationProvider == .openAICompatible {
                    Divider()
                    apiSection
                }

                if model.translationProvider == .claude {
                    Divider()
                    claudeSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shortcutsSettings: some View {
        shortcutsSection
    }

    private var promptsSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reply translation prompt")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Used when translating a reply draft back into the original language with the original text and first translation as context.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("Reset Prompt") {
                        model.resetReplyPrompt()
                    }
                    .help("Restore the default reply translation prompt")
                }

                Text("Available tokens: {{original}}, {{translation}}, {{reply}}, {{target_language}}, {{source_language}}")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                TextEditor(text: $model.replyPromptTemplate)
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
                    .frame(minHeight: 420)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Engine")
                    .font(.system(size: 14, weight: .semibold))

                ProviderSegmentedControl(
                    selection: Binding(
                        get: { model.translationProvider },
                        set: { model.selectProvider($0) }
                    ),
                    isPlamoReady: model.isPlamoReady,
                    isDisabled: model.isPreparingPlamo,
                    width: 360
                )

                if model.isPreparingPlamo {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if model.translationProvider == .plamo || !model.isPlamoReady {
                    Button("Prepare PLaMo") {
                        model.preparePlamo()
                    }
                    .disabled(model.isPreparingPlamo || model.isPlamoReady)
                }
            }

            if model.translationProvider == .plamo {
                Text(model.plamoStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(model.isPlamoStatusError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Built with PLaMo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("PLaMo is governed by the PLaMo community license.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("PLaMo ignores shortcut prompt templates and uses the selected text directly.")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Contextual reply is not available with PLaMo.")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

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

    private var shortcutsSection: some View {
        HStack(alignment: .top, spacing: 14) {
            shortcutList
            Divider()
            shortcutEditor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shortcutList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shortcut Sets")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    model.addShortcut()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Add shortcut")

                Button {
                    model.deleteSelectedShortcut()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!model.canDeleteSelectedShortcut)
                .help("Delete selected shortcut")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.shortcutProfiles) { profile in
                        Button {
                            model.selectShortcut(profile.id)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    Text(profile.shortcutLabel)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if model.selectedShortcutID == profile.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(model.selectedShortcutID == profile.id ? Color.accentColor.opacity(0.18) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 230)
    }

    private var shortcutEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.selectedShortcutProfile != nil {
                shortcutFields
            } else {
                Text("Select a shortcut set or add a new one.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var shortcutFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    TextField(
                        "Shortcut name",
                        text: Binding(
                            get: { model.selectedShortcutProfile?.name ?? "" },
                            set: { model.updateSelectedShortcutName($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.selectedShortcutProfile?.keyCode ?? KeyboardShortcut.defaultKeyCode },
                            set: { model.updateSelectedShortcutKeyCode($0) }
                        )
                    ) {
                        ForEach(KeyboardShortcut.keyOptions) { option in
                            Text(option.label).tag(option.keyCode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            HStack(spacing: 12) {
                Text("Modifiers")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)

                ForEach(KeyboardShortcutModifier.allCases) { modifier in
                    Toggle(
                        modifier.label,
                        isOn: Binding(
                            get: { model.isSelectedModifierEnabled(modifier) },
                            set: { model.setSelectedModifier(modifier, enabled: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }

            if let profile = model.selectedShortcutProfile {
                Text("Current: \(profile.shortcutLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !model.shortcutValidationMessage.isEmpty {
                Text(model.shortcutValidationMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Used by Codex and API. PLaMo ignores shortcut prompt templates.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset Prompt") {
                    model.resetSelectedPrompt()
                }
                .help("Restore the default prompt for the selected shortcut")
            }

            TextEditor(
                text: Binding(
                    get: { model.selectedShortcutProfile?.promptTemplate ?? "" },
                    set: { model.updateSelectedShortcutPrompt($0) }
                )
            )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex")
                    .font(.system(size: 14, weight: .semibold))
                Text("Uses codex exec. Leave model blank to use the Codex CLI default.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    TextField("Enter the model name", text: $model.codexModel)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude")
                    .font(.system(size: 14, weight: .semibold))
                Text("Uses claude -p. Leave model blank to use the Claude CLI default.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    TextField("Enter the model name", text: $model.claudeModel)
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
