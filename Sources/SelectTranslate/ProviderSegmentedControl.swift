import SwiftUI

struct ProviderSegmentedControl: View {
    @Binding var selection: TranslationProvider

    let isPlamoReady: Bool
    let foundationModelsAvailability: FoundationModelsAvailability
    let isDisabled: Bool
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(TranslationProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                segment(provider)

                if index < TranslationProvider.allCases.count - 1 {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .padding(2)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func segment(_ provider: TranslationProvider) -> some View {
        let selected = selection == provider
        let disabled = isDisabled ||
            (provider == .plamo && !isPlamoReady) ||
            (provider == .foundationModels && foundationModelsAvailability != .available)

        return Button {
            guard !disabled else { return }
            selection = provider
        } label: {
            Text(provider.label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .foregroundStyle(foregroundColor(selected: selected, disabled: disabled))
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .help(helpText(for: provider, disabled: disabled))
    }

    private func foregroundColor(selected: Bool, disabled: Bool) -> Color {
        if disabled {
            return .secondary
        }
        return selected ? .white : .primary
    }

    private func helpText(for provider: TranslationProvider, disabled: Bool) -> String {
        if provider == .plamo, disabled, !isPlamoReady {
            return "Download a PLaMo 3 model in Settings before selecting it"
        }
        if provider == .foundationModels {
            if let unavailableReason = foundationModelsAvailability.unavailableReason {
                return "Apple Foundation Models is unavailable: \(unavailableReason)"
            }
            return "Apple Foundation Models (on-device)"
        }
        if provider == .openAICompatible {
            return "Configure base_url, api_key, and model in Settings"
        }
        return provider.description
    }
}

/// Segmented control for PLaMo 3 sizes. Sizes that are not downloaded are shown but disabled.
struct PlamoModelSegmentedControl: View {
    @Binding var selection: PlamoModelSize

    let installedSizes: Set<PlamoModelSize>
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(PlamoModelSize.allCases.enumerated()), id: \.element.id) { index, size in
                segment(size)

                if index < PlamoModelSize.allCases.count - 1 {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .padding(2)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func segment(_ size: PlamoModelSize) -> some View {
        let selected = selection == size
        let disabled = !installedSizes.contains(size)

        return Button {
            guard !disabled else { return }
            selection = size
        } label: {
            Text(size.label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .foregroundStyle(disabled ? Color.secondary : (selected ? Color.white : Color.primary))
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected && !disabled ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .help(
            disabled
                ? "Download PLaMo 3 \(size.label) in Settings to use it"
                : "PLaMo 3 \(size.label) (\(size.repositoryID))"
        )
    }
}
