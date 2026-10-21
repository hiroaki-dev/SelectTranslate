import AppKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

extension Notification.Name {
    static let foundationModelsAvailabilityDidChange = Notification.Name("SelectTranslateFoundationModelsAvailabilityDidChange")
}

enum FoundationModelsAvailability: Equatable {
    case available
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    /// Why the on-device model cannot be used right now, or nil when it is available.
    var unavailableReason: String? {
        switch self {
        case .available:
            return nil
        case .unsupportedOS:
            return "Requires macOS 26 or later."
        case .deviceNotEligible:
            return "This Mac does not support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings."
        case .modelNotReady:
            return "The on-device model is not ready yet. It may still be downloading."
        case .unavailable:
            return "The on-device model is unavailable."
        }
    }
}

/// Translates with Apple's on-device system language model.
///
/// The package supports macOS 13, so every Foundation Models call is guarded by availability checks.
enum FoundationModelsTranslator {
    private static let appleIntelligenceSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")

    static var availability: FoundationModelsAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .appleIntelligenceNotEnabled
                case .modelNotReady:
                    return .modelNotReady
                @unknown default:
                    return .unavailable
                }
            }
        }
        return .unsupportedOS
        #else
        return .unsupportedOS
        #endif
    }

    static var unavailableReason: String? {
        availability.unavailableReason
    }

    static var isAvailable: Bool {
        availability == .available
    }

    /// Apps cannot turn on Apple Intelligence themselves, so open the Apple Intelligence & Siri settings pane.
    static func openAppleIntelligenceSettings() {
        guard let appleIntelligenceSettingsURL else { return }
        NSWorkspace.shared.open(appleIntelligenceSettingsURL)
    }

    static func respond(
        to prompt: String,
        instructions: String,
        onPartialResult: @escaping TranslationProgressHandler
    ) async throws -> String {
        if let unavailableReason {
            throw TranslationServiceError.providerNotReady(provider: .foundationModels, message: unavailableReason)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            var latestText = ""
            do {
                // Each snapshot holds the whole response generated so far, not a delta.
                for try await snapshot in session.streamResponse(to: prompt) {
                    latestText = snapshot.content
                    let partial = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !partial.isEmpty {
                        await onPartialResult(partial)
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw TranslationServiceError.invalidResponse(
                    provider: .foundationModels,
                    message: error.localizedDescription
                )
            }

            let translated = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else {
                throw TranslationServiceError.emptyResponse(provider: .foundationModels)
            }
            return translated
        }
        #endif

        throw TranslationServiceError.providerNotReady(
            provider: .foundationModels,
            message: unavailableReason ?? "The on-device model is unavailable."
        )
    }
}

/// Tracks Foundation Models availability and posts `.foundationModelsAvailabilityDidChange` when it changes.
///
/// Apple Intelligence can be turned on, and its model downloaded, while the app is running, so this polls
/// until the model settles and also refreshes whenever the app becomes active again.
@MainActor
final class FoundationModelsAvailabilityMonitor {
    static let shared = FoundationModelsAvailabilityMonitor()

    private static let pollInterval: TimeInterval = 3

    private(set) var availability = FoundationModelsTranslator.availability
    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    func start() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                FoundationModelsAvailabilityMonitor.shared.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        let latestAvailability = FoundationModelsTranslator.availability
        if latestAvailability != availability {
            availability = latestAvailability
            NotificationCenter.default.post(name: .foundationModelsAvailabilityDidChange, object: latestAvailability)
        }
        updatePolling()
    }

    private func updatePolling() {
        let mayBecomeAvailable = availability == .appleIntelligenceNotEnabled || availability == .modelNotReady
        if mayBecomeAvailable, pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
                Task { @MainActor in
                    FoundationModelsAvailabilityMonitor.shared.refresh()
                }
            }
        } else if !mayBecomeAvailable {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
