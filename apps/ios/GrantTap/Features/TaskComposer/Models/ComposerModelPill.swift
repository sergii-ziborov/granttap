import SwiftUI

/// One picker and one confirmation flow for every existing-chat model control.
struct ComposerModelPill: View {
    let agent: String
    @Binding var model: TurnModel?
    var current: String? = nil
    var catalog: TurnModelCatalog? = nil
    var fallback: String? = nil
    var hasConversation = false
    @State private var showingPicker = false
    @State private var pending: TurnModelChange?

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
        .popover(isPresented: $showingPicker) { picker }
    }

    private var picker: some View {
        CompatNavigationStack {
            List {
                Button { choose(nil) } label: {
                    Label(hasConversation ? L("Whatever the chat uses") : L("Use provider default"),
                          systemImage: model == nil ? "checkmark" : "circle")
                }
                .accessibilityIdentifier("composer.model.current")
                ForEach(available.options) { option in
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
            .navigationTitle(L("Model"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { showingPicker = false }
                }
            }
            .alert(item: $pending) { change in
                Alert(title: Text(L("Switch model?")),
                      message: Text(L("On your next message, the conversation context will be reloaded for the selected model. The provider may summarize context to fit its limits. Chat history and permissions are preserved.")),
                      primaryButton: .default(Text(L("Switch model"))) { apply(change.choice) },
                      secondaryButton: .cancel(Text(L("Cancel"))))
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(width: 420, height: 520)
        #endif
    }

    private func choose(_ choice: TurnModel?) {
        if TurnModelChange.needsConfirmation(choice: choice, selection: model, current: current,
                                             fallback: fallback, hasConversation: hasConversation) {
            pending = TurnModelChange(choice: choice)
        } else { apply(choice) }
    }

    private func apply(_ choice: TurnModel?) {
        model = choice
        showingPicker = false
    }
}
