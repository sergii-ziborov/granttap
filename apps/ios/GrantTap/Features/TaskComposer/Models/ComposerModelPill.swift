import SwiftUI

/// One picker and one confirmation flow for every existing-chat model control.
struct ComposerModelPill: View {
    let agent: String
    @Binding var model: TurnModel?
    @Binding var effort: TurnEffort?
    var fallbackEffort: TurnEffort? = nil
    var current: String? = nil
    var catalog: TurnModelCatalog? = nil
    var fallback: String? = nil
    var hasConversation = false
    var refresh: (() async -> Void)? = nil
    @State private var showingPicker = false

    private var available: TurnModelCatalog {
        catalog ?? .resolve(agent: agent, endpointId: nil, catalogs: [])
    }

    private var title: String {
        let id = model?.id ?? fallback ?? current
        if let option = available.options.first(where: { $0.id == id }) { return option.label }
        return id.flatMap { TurnModel(rawValue: $0)?.label } ?? AgentIdentity.displayName(agent)
    }

    var body: some View {
        Button { showingPicker = true } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model == nil ? Theme.muted : Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .accessibilityIdentifier("composer.model")
        .popover(isPresented: $showingPicker) {
            ComposerModelPicker(agent: agent, model: $model, effort: $effort,
                fallbackEffort: fallbackEffort, current: current, fallback: fallback,
                hasConversation: hasConversation, available: available, refresh: refresh,
                onClose: { showingPicker = false })
        }
    }

}
