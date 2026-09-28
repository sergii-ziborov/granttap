import SwiftUI

/// What the next turns from GrantTap should answer with.
///
/// Model and effort are both per-chat choices that fall back to the agent-wide
/// default, and both are shown only to providers whose CLI actually accepts
/// them — an option that would be dropped on the way is worse than no option.
struct ChatTurnOverridesSection: View {
    let sessionId: String
    let agent: String
    @ObservedObject var model: AppModel

    private var models: [TurnModel] { TurnModel.supported(by: agent) }
    private var efforts: [TurnEffort] { TurnEffort.supported(by: agent) }

    var body: some View {
        if !models.isEmpty || !efforts.isEmpty {
            Section {
                if !models.isEmpty {
                    Picker(L("Model"), selection: modelBinding) {
                        Text(L("Keep current model")).tag(TurnModel?.none)
                        ForEach(models) { choice in
                            Text(choice.label).tag(TurnModel?.some(choice))
                        }
                    }
                }
                if !efforts.isEmpty {
                    Picker(L("Effort"), selection: effortBinding) {
                        Text(L("Keep current effort")).tag(TurnEffort?.none)
                        ForEach(efforts) { choice in
                            Text(choice.label).tag(TurnEffort?.some(choice))
                        }
                    }
                }
            } header: {
                Text(L("Model"))
            } footer: {
                Text(L("Applies to future turns sent from GrantTap."))
                    .font(.system(size: 11))
            }
        }
    }

    var modelBinding: Binding<TurnModel?> {
        Binding(
            get: { model.turnOverrides.chatOverrides(sessionId).model },
            set: { choice in
                var current = model.turnOverrides.chatOverrides(sessionId)
                current.model = choice
                model.turnOverrides.setChatOverrides(current, for: sessionId)
            }
        )
    }

    var effortBinding: Binding<TurnEffort?> {
        Binding(
            get: { model.turnOverrides.chatOverrides(sessionId).effort },
            set: { choice in
                var current = model.turnOverrides.chatOverrides(sessionId)
                current.effort = choice
                model.turnOverrides.setChatOverrides(current, for: sessionId)
            }
        )
    }
}
