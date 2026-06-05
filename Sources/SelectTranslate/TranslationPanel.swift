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
    @Published var isLoading: Bool = false
    @Published var isBackTranslating: Bool = false
    @Published var isBackTranslationError: Bool = false
    @Published var isError: Bool = false
    @Published var canBackTranslate: Bool = false
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
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        translatedText = ""
        message = ""
        directionLabel = ""
        title = "SelectTranslate"
        backTranslatedText = ""
        backTranslationMessage = ""
        isBackTranslating = false
        isBackTranslationError = false
        isError = false
        canBackTranslate = false
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

    var reasoningEffort: ReasoningEffort {
        model.reasoningEffort
    }

    var translationProvider: TranslationProvider {
        model.translationProvider
    }

    var sourceText: String {
        model.sourceText
    }

    func setTranslationProvider(_ provider: TranslationProvider) {
        model.translationProvider = provider
    }

    func activateOnNextShow() {
        shouldActivateOnNextShow = true
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
        model.isLoading = true
        model.isBackTranslating = false
        model.isBackTranslationError = false
        model.isError = false
        model.canBackTranslate = false
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
        model.isLoading = false
        model.isBackTranslating = false
        model.isBackTranslationError = false
        model.isError = false
        model.canBackTranslate = true
        showPanel()
    }

    func showError(source: String?, title: String, message: String) {
        model.sourceText = source ?? ""
        model.translatedText = ""
        model.directionLabel = ""
        model.title = title
        model.message = message
        model.backTranslatedText = ""
        model.backTranslationMessage = ""
        model.isLoading = false
        model.isBackTranslating = false
        model.isBackTranslationError = false
        model.isError = true
        model.canBackTranslate = false
        showPanel()
    }

    func showPreparationLoading(title: String, message: String) {
        model.translatedText = ""
        model.directionLabel = ""
        model.title = title
        model.message = message
        model.backTranslatedText = ""
        model.backTranslationMessage = ""
        model.isLoading = true
        model.isBackTranslating = false
        model.isBackTranslationError = false
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

    func showReady(isAccessibilityTrusted: Bool) {
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
        model.isLoading = false
        model.isBackTranslating = false
        model.isBackTranslationError = false
        model.isError = false
        model.canBackTranslate = false
        showPanel()
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

    private func showPanel() {
        let shouldCenter = panel == nil
        let panel = panel ?? makePanel()
        self.panel = panel
        if shouldCenter {
            panel.center()
        }
        if shouldActivateOnNextShow {
            shouldActivateOnNextShow = false
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 760, height: 420)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "SelectTranslate"
        panel.minSize = NSSize(width: 720, height: 360)
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenAuxiliary]
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
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.isError {
                errorBody
            } else {
                translationBody
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onChange(of: model.reasoningEffort) { newEffort in
            effortChanged(newEffort)
        }
        .onChange(of: model.translationProvider) { newProvider in
            providerChanged(newProvider)
        }
    }

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

            if model.translationProvider == .codex {
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
                isDisabled: model.isLoading || model.isBackTranslating,
                width: 198
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
            .disabled(model.isLoading || model.isBackTranslating || model.translationProvider != .codex)
            .help("Reasoning effort passed to codex exec")
        }
    }

    private var translationBody: some View {
        HStack(alignment: .top, spacing: 12) {
            originalPane
            sourceTranslateButton
            translationPane
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
                    .disabled(model.isLoading || model.isBackTranslating)
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

    private var canTranslateSource: Bool {
        !model.isLoading &&
            !model.isBackTranslating &&
            !model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            OriginalTextEditor(
                text: Binding(
                    get: { model.sourceText },
                    set: { model.updateSourceTextFromUser($0) }
                ),
                isDisabled: model.isLoading || model.isBackTranslating,
                onTranslate: translateSource
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

private struct OriginalTextEditor: NSViewRepresentable {
    @Binding var text: String
    let isDisabled: Bool
    let onTranslate: () -> Void

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
        var parent: OriginalTextEditor
        weak var textView: NSTextView?

        init(_ parent: OriginalTextEditor) {
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
            parent.onTranslate()
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
