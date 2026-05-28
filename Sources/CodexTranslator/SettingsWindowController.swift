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
        let model = PromptSettingsModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Codex Translator Settings"
        window.minSize = NSSize(width: 600, height: 420)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PromptSettingsView(model: model) { [weak window] in
                window?.close()
            }
        )

        return window
    }
}

@MainActor
private final class PromptSettingsModel: ObservableObject {
    @Published var promptTemplate: String {
        didSet {
            PromptSettings.template = promptTemplate
        }
    }

    init() {
        promptTemplate = PromptSettings.template
    }

    func reset() {
        PromptSettings.resetTemplate()
        promptTemplate = PromptSettings.defaultTemplate
    }
}

private struct PromptSettingsView: View {
    @ObservedObject var model: PromptSettingsModel
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
        .frame(minWidth: 600, minHeight: 420)
    }
}
