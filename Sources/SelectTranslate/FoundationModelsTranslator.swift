import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Translates with Apple's on-device system language model.
///
/// The package supports macOS 13, so every Foundation Models call is guarded by availability checks.
enum FoundationModelsTranslator {
    /// Why the on-device model cannot be used right now, or nil when it is available.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return "This Mac does not support Apple Intelligence."
                case .appleIntelligenceNotEnabled:
                    return "Turn on Apple Intelligence in System Settings."
                case .modelNotReady:
                    return "The on-device model is not ready yet. It may still be downloading."
                @unknown default:
                    return "The on-device model is unavailable."
                }
            }
        }
        return "Requires macOS 26 or later."
        #else
        return "This build does not include Foundation Models support."
        #endif
    }

    static var isAvailable: Bool {
        unavailableReason == nil
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
