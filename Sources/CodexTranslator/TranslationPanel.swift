import AppKit
import SwiftUI

@MainActor
final class TranslationPanelModel: ObservableObject {
    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var directionLabel: String = ""
    @Published var title: String = "Codex Translate"
    @Published var message: String = ""
    @Published var isLoading: Bool = false
    @Published var isError: Bool = false
}

@MainActor
final class TranslationPanelController {
    private let model = TranslationPanelModel()
    private var panel: NSPanel?

    func showLoading(source: String, direction: TranslationDirection) {
        model.sourceText = source
        model.translatedText = ""
        model.directionLabel = direction.label
        model.title = "Translating"
        model.message = "codex exec is translating the selected text."
        model.isLoading = true
        model.isError = false
        showPanel()
    }

    func showResult(source: String, translation: String, direction: TranslationDirection) {
        model.sourceText = source
        model.translatedText = translation
        model.directionLabel = direction.label
        model.title = "Codex Translate"
        model.message = ""
        model.isLoading = false
        model.isError = false
        showPanel()
    }

    func showError(source: String?, title: String, message: String) {
        model.sourceText = source ?? ""
        model.translatedText = ""
        model.directionLabel = ""
        model.title = title
        model.message = message
        model.isLoading = false
        model.isError = true
        showPanel()
    }

    func showReady(isAccessibilityTrusted: Bool) {
        model.sourceText = """
        1. Select text in any app.
        2. Press Control + F.
        3. The original and translation will appear here.
        """

        if isAccessibilityTrusted {
            model.translatedText = "Ready. Accessibility permission is enabled."
        } else {
            model.translatedText = "Accessibility permission is not enabled yet. Use the Codex menu bar item and choose Open Accessibility Settings."
        }

        model.directionLabel = "Control + F"
        model.title = "Codex Translator is Running"
        model.message = ""
        model.isLoading = false
        model.isError = false
        showPanel()
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 760, height: 420)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Codex Translate"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: TranslationOverlayView(model: model) { [weak panel] in
            panel?.close()
        })

        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screenContainingMouse ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation

        var origin = NSPoint(
            x: mouse.x - (size.width / 2),
            y: mouse.y - size.height - 18
        )

        if origin.x < visibleFrame.minX + 16 {
            origin.x = visibleFrame.minX + 16
        }
        if origin.x + size.width > visibleFrame.maxX - 16 {
            origin.x = visibleFrame.maxX - size.width - 16
        }
        if origin.y < visibleFrame.minY + 16 {
            origin.y = visibleFrame.minY + 16
        }
        if origin.y + size.height > visibleFrame.maxY - 16 {
            origin.y = visibleFrame.maxY - size.height - 16
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

private struct TranslationOverlayView: View {
    @ObservedObject var model: TranslationPanelModel
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
        .frame(width: 760, height: 420)
        .background(.regularMaterial)
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

    private var translationBody: some View {
        HStack(spacing: 12) {
            textPane(title: "Original", text: model.sourceText, placeholder: "")
            textPane(title: "Translation", text: model.translatedText, placeholder: model.message)
        }
    }

    private var errorBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.message)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !model.sourceText.isEmpty {
                textPane(title: "Original", text: model.sourceText, placeholder: "")
            }
            Spacer()
        }
    }

    private func textPane(title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if title == "Translation", !text.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Copy translation")
                }
            }

            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: 15))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
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
}

private extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { screen in
            screen.frame.contains(mouse)
        }
    }
}
