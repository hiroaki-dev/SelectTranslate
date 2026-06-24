import AppKit
import Carbon
import SwiftUI

@MainActor
final class TranslationPanelModel: ObservableObject {
    private static let effortDefaultsKey = "reasoningEffort"
    private var plamoSetupObserver: NSObjectProtocol?

    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var directionLabel: String = ""
    @Published var title: String = "SelectTranslate"
    @Published var message: String = ""
    @Published var backTranslatedText: String = ""
    @Published var backTranslationMessage: String = ""
    @Published var replyDraftText: String = ""
    @Published var translatedReplyText: String = ""
    @Published var replyTranslationMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var isBackTranslating: Bool = false
    @Published var isReplyTranslating: Bool = false
    @Published var isBackTranslationError: Bool = false
    @Published var isReplyTranslationError: Bool = false
    @Published var isError: Bool = false
    @Published var canBackTranslate: Bool = false
    @Published var historyItems: [TranslationHistoryItem] = []
    @Published var selectedHistoryID: Int64?
    @Published var isPlamoReady: Bool
    @Published var reasoningEffort: ReasoningEffort {
        didSet {
            UserDefaults.standard.set(reasoningEffort.rawValue, forKey: Self.effortDefaultsKey)
        }
    }
    @Published var translationProvider: TranslationProvider {
        didSet {
            if oldValue != translationProvider {
                TranslationPreferences.translationProvider = translationProvider
            }
        }
    }

    init() {
        let savedValue = UserDefaults.standard.string(forKey: Self.effortDefaultsKey)
        reasoningEffort = savedValue.flatMap(ReasoningEffort.init(rawValue:)) ?? .low
        isPlamoReady = PlamoSetupService.isSetupComplete
        translationProvider = TranslationPreferences.translationProvider
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
        if let plamoSetupObserver {
            NotificationCenter.default.removeObserver(plamoSetupObserver)
        }
    }

    func setProviderFromUserSelection(_ provider: TranslationProvider) {
        if provider == .plamo, !isPlamoReady {
            message = "Prepare PLaMo in Settings before selecting it."
            return
        }

        translationProvider = provider
    }

    func updateSourceTextFromUser(_ text: String) {
        guard sourceText != text else { return }

        sourceText = text
        selectedHistoryID = nil
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        translatedText = ""
        message = ""
        directionLabel = ""
        title = "SelectTranslate"
        backTranslatedText = ""
        backTranslationMessage = ""
        clearReplyState(clearDraft: true)
        isBackTranslating = false
        isReplyTranslating = false
        isBackTranslationError = false
        isReplyTranslationError = false
        isError = false
        canBackTranslate = false
    }

    func updateReplyDraftTextFromUser(_ text: String) {
        guard replyDraftText != text else { return }

        replyDraftText = text
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        clearReplyState(clearDraft: false)
    }

    func setHistoryItems(_ items: [TranslationHistoryItem]) {
        historyItems = items
        if let selectedHistoryID, !items.contains(where: { $0.id == selectedHistoryID }) {
            self.selectedHistoryID = nil
        }
    }

    func prependHistoryItem(_ item: TranslationHistoryItem, limit: Int = 200) {
        var items = historyItems.filter { $0.id != item.id }
        items.insert(item, at: 0)
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        historyItems = items
        selectedHistoryID = item.id
    }

    func updateHistoryItem(_ item: TranslationHistoryItem) {
        guard let index = historyItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        historyItems[index] = item
    }

    func showHistoryItem(_ item: TranslationHistoryItem) {
        sourceText = item.originalText
        translatedText = item.translatedText
        directionLabel = "\(item.directionLabel) · \(item.engineLabel)"
        title = "\(item.engineLabel) Translate"
        message = ""
        backTranslatedText = ""
        backTranslationMessage = ""
        replyDraftText = item.replyDraftText
        translatedReplyText = item.translatedReplyText
        replyTranslationMessage = ""
        isLoading = false
        isBackTranslating = false
        isReplyTranslating = false
        isBackTranslationError = false
        isReplyTranslationError = false
        isError = false
        canBackTranslate = true
        selectedHistoryID = item.id
    }

    func showNewTranslation() {
        sourceText = ""
        translatedText = ""
        directionLabel = ""
        title = "New Translation"
        message = "Type or paste text in Original, then press the translate button."
        backTranslatedText = ""
        backTranslationMessage = ""
        clearReplyState(clearDraft: true)
        isLoading = false
        isBackTranslating = false
        isReplyTranslating = false
        isBackTranslationError = false
        isReplyTranslationError = false
        isError = false
        canBackTranslate = false
        selectedHistoryID = nil
    }

    func clearReplyState(clearDraft: Bool) {
        if clearDraft {
            replyDraftText = ""
        }
        translatedReplyText = ""
        replyTranslationMessage = ""
        isReplyTranslating = false
        isReplyTranslationError = false
    }

    private func refreshPlamoReadiness() {
        isPlamoReady = PlamoSetupService.isSetupComplete
        if !isPlamoReady, translationProvider == .plamo {
            translationProvider = .codex
        }
    }
}

@MainActor
final class TranslationPanelController {
    private let model = TranslationPanelModel()
    private var panel: NSPanel?
    private var shouldActivateOnNextShow = false

    var onReasoningEffortChanged: ((ReasoningEffort) -> Void)?
    var onTranslationProviderChanged: ((TranslationProvider) -> Void)?
    var onBackTranslateRequested: (() -> Void)?
    var onSourceTranslateRequested: (() -> Void)?
    var onReplyTranslateRequested: (() -> Void)?
    var onHistoryItemSelected: ((TranslationHistoryItem) -> Void)?
    var onNewTranslationRequested: (() -> Void)?

    var reasoningEffort: ReasoningEffort {
        model.reasoningEffort
    }

    var translationProvider: TranslationProvider {
        model.translationProvider
    }

    var sourceText: String {
        model.sourceText
    }

    var replyDraftText: String {
        model.replyDraftText
    }

    func setTranslationProvider(_ provider: TranslationProvider) {
        model.translationProvider = provider
    }

    func activateOnNextShow() {
        shouldActivateOnNextShow = true
    }

    func cancelActivationOnNextShow() {
        shouldActivateOnNextShow = false
    }

    func setHistoryItems(_ items: [TranslationHistoryItem]) {
        model.setHistoryItems(items)
    }

    func prependHistoryItem(_ item: TranslationHistoryItem) {
        model.prependHistoryItem(item)
    }

    func updateHistoryItem(_ item: TranslationHistoryItem) {
        model.updateHistoryItem(item)
    }

    func clearReplyState(clearDraft: Bool) {
        model.clearReplyState(clearDraft: clearDraft)
    }

    func showHistoryItem(_ item: TranslationHistoryItem) {
        model.showHistoryItem(item)
        showPanel()
    }

    func showNewTranslation() {
        model.showNewTranslation()
        showPanel()
    }

    func showLoading(
        source: String,
        direction: TranslationDirection,
        provider: TranslationProvider,
        shortcutProfile: ShortcutProfile
    ) {
        model.sourceText = source
        model.translatedText = ""
        model.directionLabel = Self.contextLabel(direction: direction, shortcutProfile: shortcutProfile)
        model.title = "Translating"
        model.message = Self.loadingMessage(provider: provider)
        model.backTranslatedText = ""
        model.backTranslationMessage = ""
        model.clearReplyState(clearDraft: false)
        model.isLoading = true
        model.isBackTranslating = false
        model.isReplyTranslating = false
        model.isBackTranslationError = false
        model.isReplyTranslationError = false
        model.isError = false
        model.canBackTranslate = false
        model.selectedHistoryID = nil
        showPanel()
    }

    func showResult(
        source: String,
        translation: String,
        direction: TranslationDirection,
        provider: TranslationProvider,
        shortcutProfile: ShortcutProfile
    ) {
        model.sourceText = source
        model.translatedText = translation
        model.directionLabel = Self.contextLabel(direction: direction, shortcutProfile: shortcutProfile)
        model.title = "\(provider.label) Translate"
        model.message = ""
        model.backTranslatedText = ""
        model.backTranslationMessage = ""
        model.clearReplyState(clearDraft: false)
        model.isLoading = false
        model.isBackTranslating = false
        model.isReplyTranslating = false
        model.isBackTranslationError = false
        model.isReplyTranslationError = false
        model.isError = false
        model.canBackTranslate = true
        model.selectedHistoryID = nil
        showPanel()
    }

    func showStreamingTranslation(_ text: String) {
        guard model.isLoading else { return }
        model.translatedText = text
        model.message = ""
        model.isError = false
    }

    func showError(source: String?, title: String, message: String, activates: Bool = true) {
        model.sourceText = source ?? ""
        model.translatedText = ""
        model.directionLabel = ""
        model.title = title
        model.message = message
        model.backTranslatedText = ""
        model.backTranslationMessage = ""
        model.clearReplyState(clearDraft: true)
        model.isLoading = false
        model.isBackTranslating = false
        model.isReplyTranslating = false
        model.isBackTranslationError = false
        model.isReplyTranslationError = false
        model.isError = true
        model.canBackTranslate = false
        model.selectedHistoryID = nil
        showPanel(activates: activates)
    }

    func showPreparationLoading(title: String, message: String) {
        model.translatedText = ""
        model.directionLabel = ""
        model.title = title
        model.message = message
        model.backTranslatedText = ""
        model.backTranslationMessage = ""
        model.clearReplyState(clearDraft: true)
        model.isLoading = true
        model.isBackTranslating = false
        model.isReplyTranslating = false
        model.isBackTranslationError = false
        model.isReplyTranslationError = false
        model.isError = false
        model.canBackTranslate = false
        showPanel()
    }

    func showBackTranslationLoading() {
        model.backTranslatedText = ""
        model.backTranslationMessage = "Translating the result back to the original language."
        model.isBackTranslating = true
        model.isBackTranslationError = false
        showPanel()
    }

    func showStreamingBackTranslation(_ text: String) {
        guard model.isBackTranslating else { return }
        model.backTranslatedText = text
        model.backTranslationMessage = ""
        model.isBackTranslationError = false
    }

    func showBackTranslationResult(_ text: String) {
        model.backTranslatedText = text
        model.backTranslationMessage = ""
        model.isBackTranslating = false
        model.isBackTranslationError = false
        showPanel()
    }

    func showBackTranslationError(_ message: String) {
        model.backTranslatedText = ""
        model.backTranslationMessage = message
        model.isBackTranslating = false
        model.isBackTranslationError = true
        showPanel()
    }

    func showReplyTranslationLoading(targetLanguage: String) {
        model.translatedReplyText = ""
        model.replyTranslationMessage = "Translating the reply into \(targetLanguage)."
        model.isReplyTranslating = true
        model.isReplyTranslationError = false
        showPanel()
    }

    func showStreamingReplyTranslation(_ text: String) {
        guard model.isReplyTranslating else { return }
        model.translatedReplyText = text
        model.replyTranslationMessage = ""
        model.isReplyTranslationError = false
    }

    func showReplyTranslationResult(_ text: String) {
        model.translatedReplyText = text
        model.replyTranslationMessage = ""
        model.isReplyTranslating = false
        model.isReplyTranslationError = false
        showPanel()
    }

    func showReplyTranslationError(_ message: String) {
        model.translatedReplyText = ""
        model.replyTranslationMessage = message
        model.isReplyTranslating = false
        model.isReplyTranslationError = true
        showPanel()
    }

    func showReady(isAccessibilityTrusted: Bool, activates: Bool = true) {
        model.sourceText = ""

        if isAccessibilityTrusted {
            model.translatedText = "Ready. Accessibility permission is enabled."
        } else {
            model.translatedText = "Accessibility permission is not enabled yet. Use the SelectTranslate menu bar item and choose Open Accessibility Settings."
        }

        model.directionLabel = PromptSettings.defaultShortcutProfile.shortcutLabel
        model.title = "SelectTranslate is Running"
        model.message = ""
        model.backTranslatedText = ""
        model.backTranslationMessage = ""
        model.clearReplyState(clearDraft: true)
        model.isLoading = false
        model.isBackTranslating = false
        model.isReplyTranslating = false
        model.isBackTranslationError = false
        model.isReplyTranslationError = false
        model.isError = false
        model.canBackTranslate = false
        model.selectedHistoryID = nil
        showPanel(activates: activates)
    }

    private static func contextLabel(direction: TranslationDirection, shortcutProfile: ShortcutProfile) -> String {
        let name = shortcutContextName(shortcutProfile)
        guard !name.isEmpty else {
            return direction.label
        }

        return "\(direction.label) · \(name)"
    }

    private static func shortcutContextName(_ shortcutProfile: ShortcutProfile) -> String {
        let name = shortcutProfile.displayName
        return isPlaceholderShortcutName(name) ? "" : name
    }

    private static func isPlaceholderShortcutName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return true }

        if trimmedName == "Untitled Shortcut" || trimmedName == "New Shortcut" {
            return true
        }

        return trimmedName.range(
            of: #"^New Shortcut \d+$"#,
            options: [.regularExpression]
        ) != nil
    }

    private static func loadingMessage(provider: TranslationProvider) -> String {
        if provider == .plamo {
            return "PLaMo MLX is translating the selected text. Shortcut prompt templates are ignored by PLaMo."
        }

        return "\(provider.description) is translating the selected text."
    }

    private func showPanel(activates: Bool = true) {
        let shouldCenter = panel == nil
        let panel = panel ?? makePanel()
        self.panel = panel
        if shouldCenter {
            panel.center()
        }
        if shouldActivateOnNextShow, activates {
            shouldActivateOnNextShow = false
            NSApp.activate(ignoringOtherApps: true)
        }
        if activates {
            panel.makeKeyAndOrderFront(nil)
        } else {
            shouldActivateOnNextShow = false
            panel.orderFront(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 980, height: 640)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "SelectTranslate"
        panel.minSize = NSSize(width: 900, height: 520)
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: TranslationOverlayView(
                model: model,
                effortChanged: { [weak self] effort in
                    self?.onReasoningEffortChanged?(effort)
                },
                providerChanged: { [weak self] provider in
                    self?.onTranslationProviderChanged?(provider)
                },
                backTranslate: { [weak self] in
                    self?.onBackTranslateRequested?()
                },
                translateSource: { [weak self] in
                    self?.onSourceTranslateRequested?()
                },
                translateReply: { [weak self] in
                    self?.onReplyTranslateRequested?()
                },
                selectHistoryItem: { [weak self] item in
                    self?.onHistoryItemSelected?(item)
                },
                newTranslation: { [weak self] in
                    self?.onNewTranslationRequested?()
                },
                close: { [weak panel] in
                    panel?.close()
                }
            )
        )

        return panel
    }
}

private struct TranslationOverlayView: View {
    @ObservedObject var model: TranslationPanelModel
    let effortChanged: (ReasoningEffort) -> Void
    let providerChanged: (TranslationProvider) -> Void
    let backTranslate: () -> Void
    let translateSource: () -> Void
    let translateReply: () -> Void
    let selectHistoryItem: (TranslationHistoryItem) -> Void
    let newTranslation: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            historySidebar
            Divider()
            mainContent
        }
        .frame(minWidth: 900, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onChange(of: model.reasoningEffort) { newEffort in
            effortChanged(newEffort)
        }
        .onChange(of: model.translationProvider) { newProvider in
            providerChanged(newProvider)
        }
    }

    private var historySidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: newTranslation) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Translation")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .foregroundStyle(isBusy ? .secondary : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .help("Start a new manual translation")

            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if model.historyItems.isEmpty {
                Text("No history yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.historyItems) { item in
                            historyRow(item)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 230, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.isError {
                errorBody
            } else {
                translationBody
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func historyRow(_ item: TranslationHistoryItem) -> some View {
        Button {
            selectHistoryItem(item)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.historyDateFormatter.string(from: item.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(item.originalPreview.isEmpty ? "(empty)" : item.originalPreview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.engineLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(model.selectedHistoryID == item.id ? Color.accentColor.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isError ? "exclamationmark.triangle.fill" : "globe")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(model.isError ? .orange : .blue)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                if !model.directionLabel.isEmpty {
                    Text(model.directionLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            headerControls

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            providerPicker

            if model.translationProvider == .codex || model.translationProvider == .claude {
                effortPicker
            }
        }
    }

    private var providerPicker: some View {
        HStack(spacing: 6) {
            Text("Engine")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            ProviderSegmentedControl(
                selection: Binding(
                    get: { model.translationProvider },
                    set: { model.setProviderFromUserSelection($0) }
                ),
                isPlamoReady: model.isPlamoReady,
                isDisabled: isBusy,
                width: 272
            )
        }
    }

    private var effortPicker: some View {
        HStack(spacing: 6) {
            Text("Effort")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Picker("", selection: $model.reasoningEffort) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(effort.label).tag(effort)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
            .disabled(
                isBusy ||
                    (model.translationProvider != .codex && model.translationProvider != .claude)
            )
            .help("Reasoning effort passed to the selected CLI engine")
        }
    }

    private var translationBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                originalPane
                sourceTranslateButton
                translationPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shouldShowReplyWorkflow {
                replyWorkflow
                    .frame(height: 190)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorBody: some View {
        HStack(alignment: .top, spacing: 12) {
            originalPane
            sourceTranslateButton
            simpleTextPane(title: "Details", text: model.message, placeholder: "")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var originalPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Original")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .frame(height: 28)

            editableTextBox(placeholder: "")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceTranslateButton: some View {
        VStack {
            Spacer()
            Button(action: translateSource) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!canTranslateSource)
            .help("Translate original text")
            Spacer()
        }
        .frame(width: 34)
        .frame(maxHeight: .infinity)
    }

    private func simpleTextPane(title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .frame(height: 28)

            textBox(text: text, placeholder: placeholder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var translationPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Translation")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()

                if model.canBackTranslate {
                    Button(action: backTranslate) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .help("Translate back to the original language")
                }

                if !model.translatedText.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.translatedText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Copy translation")
                }
            }
            .frame(height: 28)

            VStack(alignment: .leading, spacing: 0) {
                scrollText(
                    text: model.translatedText,
                    placeholder: model.message,
                    isError: false
                )
                .frame(maxHeight: .infinity)

                if shouldShowBackTranslation {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Back translation")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if model.isBackTranslating {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        scrollText(
                            text: model.backTranslatedText,
                            placeholder: model.backTranslationMessage,
                            isError: model.isBackTranslationError
                        )
                    }
                    .padding(12)
                    .frame(maxHeight: 150)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowBackTranslation: Bool {
        model.isBackTranslating || !model.backTranslatedText.isEmpty || !model.backTranslationMessage.isEmpty
    }

    private var shouldShowReplyWorkflow: Bool {
        model.translationProvider != .plamo &&
            (
                model.canBackTranslate ||
                    !model.replyDraftText.isEmpty ||
                    !model.translatedReplyText.isEmpty ||
                    !model.replyTranslationMessage.isEmpty
            )
    }

    private var isBusy: Bool {
        model.isLoading || model.isBackTranslating || model.isReplyTranslating
    }

    private var canTranslateSource: Bool {
        !isBusy &&
            !model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTranslateReply: Bool {
        !isBusy &&
            model.translationProvider != .plamo &&
            model.canBackTranslate &&
            !model.replyDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var replyWorkflow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Contextual reply")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if model.isReplyTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
            .frame(height: 20)

            HStack(alignment: .top, spacing: 12) {
                replyDraftPane
                replyTranslateButton
                translatedReplyPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var replyDraftPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reply draft")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            commandReturnTextBox(
                text: Binding(
                    get: { model.replyDraftText },
                    set: { model.updateReplyDraftTextFromUser($0) }
                ),
                placeholder: "Write a reply, then press Command + Return.",
                isDisabled: isBusy,
                onSubmit: translateReply
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var replyTranslateButton: some View {
        VStack {
            Spacer()
            Button(action: translateReply) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!canTranslateReply)
            .help("Translate reply with context")
            Spacer()
        }
        .frame(width: 34)
        .frame(maxHeight: .infinity)
    }

    private var translatedReplyPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Translated reply")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !model.translatedReplyText.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.translatedReplyText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Copy translated reply")
                }
            }

            scrollText(
                text: model.translatedReplyText,
                placeholder: replyTranslationPlaceholder,
                isError: model.isReplyTranslationError
            )
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var replyTranslationPlaceholder: String {
        model.replyTranslationMessage.isEmpty
            ? "Translated reply will appear here."
            : model.replyTranslationMessage
    }

    private func textBox(text: String, placeholder: String) -> some View {
        scrollText(text: text, placeholder: placeholder, isError: false)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }

    private func editableTextBox(placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            CommandReturnTextEditor(
                text: Binding(
                    get: { model.sourceText },
                    set: { model.updateSourceTextFromUser($0) }
                ),
                isDisabled: isBusy,
                onSubmit: translateSource
            )

            if model.sourceText.isEmpty, !placeholder.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func commandReturnTextBox(
        text: Binding<String>,
        placeholder: String,
        isDisabled: Bool,
        onSubmit: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topLeading) {
            CommandReturnTextEditor(
                text: text,
                isDisabled: isDisabled,
                onSubmit: onSubmit
            )

            if text.wrappedValue.isEmpty, !placeholder.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func scrollText(text: String, placeholder: String, isError: Bool) -> some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : text)
                .font(.system(size: 15))
                .foregroundStyle(text.isEmpty ? (isError ? .red : .secondary) : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}

private struct CommandReturnTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isDisabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = CommandReturnTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.onCommandReturn = {
            context.coordinator.translate()
        }
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? CommandReturnTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = !isDisabled
        textView.isSelectable = true
        textView.onCommandReturn = {
            context.coordinator.translate()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandReturnTextEditor
        weak var textView: NSTextView?

        init(_ parent: CommandReturnTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func translate() {
            let sourceText = textView?.string ?? parent.text
            guard !parent.isDisabled,
                  !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            parent.text = sourceText
            parent.onSubmit()
        }
    }

    final class CommandReturnTextView: NSTextView {
        var onCommandReturn: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isReturnKey = event.keyCode == UInt16(kVK_Return) ||
                event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
            if flags.contains(.command), isReturnKey {
                onCommandReturn?()
                return
            }

            super.keyDown(with: event)
        }
    }
}
