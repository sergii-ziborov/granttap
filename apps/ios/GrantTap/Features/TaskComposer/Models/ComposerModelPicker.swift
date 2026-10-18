import SwiftUI

/// Owns confirmation state inside the presented picker. Catalyst popovers do
/// not reliably present alerts driven by State on the outside anchor button.
struct ComposerModelPicker: View {
    let agent: String
    @Binding var model: TurnModel?
    @Binding var effort: TurnEffort?
    let fallbackEffort: TurnEffort?
    let current: String?
    let fallback: String?
    let hasConversation: Bool
    let available: TurnModelCatalog
    let refresh: (() async -> Void)?
    var contextTokens: Int? = nil
    var contextWindow: Int? = nil
    let onClose: () -> Void
    @State private var pending: TurnModelChange?

    var body: some View {
        ChatSheetNavigation(title: L("Model"), doneIdentifier: "composer.model.done",
                            onClose: onClose) {
            List {
                ComposerEffortPicker(agent: agent, selection: $effort,
                    fallback: fallbackEffort,
                    choices: available.efforts(for: model?.id ?? fallback ?? current, agent: agent))
                Section(L("Model")) {
                    Button { choose(nil) } label: {
                        Label(hasConversation ? L("Whatever the chat uses") : L("Use provider default"),
                              systemImage: model == nil ? "checkmark" : "circle")
                    }
                    .accessibilityIdentifier("composer.model.current")
                }
                ForEach(available.groups(agent: agent)) { group in
                    Section(group.title) {
                    ForEach(group.options) { option in
                        Button { choose(option.model) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: model == option.model ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.label).font(.body.weight(.semibold))
                                    Text(option.detail).font(.caption).foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .accessibilityIdentifier("composer.model.select.\(option.id)")
                    }
                    }
                }
                if !available.accountUsage.isEmpty {
                    Section(L("Subscription limits")) { ProviderAccountUsageRows(rows: available.accountUsage) }
                }
                if hasConversation {
                    Section(L("Context")) {
                        if let tokens = contextTokens, tokens > 0 {
                            HStack { Text(L("Reported context")); Spacer()
                                Text("\(tokens.formatted()) \(L("tokens"))") }
                            if let window = contextWindow, window > 0 {
                                Text("\(Int((Double(tokens) / Double(window) * 100).rounded()))% \(L("of context window"))")
                            }
                        } else { Text(L("Context size has not been reported by the provider.")) }
                        Text(L("Switching models reloads conversation context and can consume input tokens. Cached input and the amount billed depend on the provider; an exact charge is not reported here."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Section {
                    if available.stale {
                        Text(L("Current models have not been reported by this computer. Open the provider to refresh its model catalog."))
                    } else if let checkedAt = available.checkedAt {
                        Text(L("Provider catalog updated")) + Text(" ")
                            + Text(Date(timeIntervalSince1970: checkedAt / 1_000), style: .date)
                            + Text(" ") + Text(Date(timeIntervalSince1970: checkedAt / 1_000), style: .time)
                    }
                    Text(L("Availability, limits and billing depend on your provider account."))
                    Text(L("Applies to the next message sent from GrantTap."))
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
            .refreshable { await refresh?() }
            .task { await refresh?() }
        }
        .alert(L("Switch model?"), isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { change in
            Button(L("Switch model")) { apply(change.choice) }
            Button(L("Cancel"), role: .cancel) { pending = nil }
        } message: { _ in
            Text(L("On your next message, the conversation context will be reloaded for the selected model. This can consume input tokens; cached input and billing depend on the provider. The provider may summarize context to fit its limits. Chat history and permissions are preserved."))
        }
        #if targetEnvironment(macCatalyst)
        .frame(width: 420, height: 660)
        #endif
    }

    private func choose(_ choice: TurnModel?) {
        if TurnModelChange.needsConfirmation(choice: choice, selection: model, current: current,
                                             fallback: fallback, hasConversation: hasConversation) {
            pending = TurnModelChange(choice: choice)
        } else { apply(choice) }
    }

    private func apply(_ choice: TurnModel?) {
        if let effort, !available.efforts(for: choice?.id ?? fallback ?? current, agent: agent).contains(effort) {
            self.effort = nil
        }
        model = choice
        onClose()
    }
}
