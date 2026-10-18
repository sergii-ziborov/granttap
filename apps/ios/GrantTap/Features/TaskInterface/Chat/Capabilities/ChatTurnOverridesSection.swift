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

    private var supportsModel: Bool { ["codex", "claude", "cursor", "grok"].contains(AgentIdentity.normalize(agent)) }
    private var efforts: [TurnEffort] { TurnEffort.supported(by: agent) }

    var body: some View {
        if supportsModel || !efforts.isEmpty {
            Section {
                if supportsModel {
                    HStack {
                        Text(L("Model"))
                        Spacer()
                        ComposerModelPill(agent: agent, model: modelBinding, effort: effortBinding,
                            fallbackEffort: model.turnOverrides.agentDefaults(for: agent).effort
                                ?? session?.effort.flatMap(TurnEffort.init(rawValue:)),
                            current: session?.model,
                            catalog: model.turnModelCatalog(agent: agent, session: session),
                            fallback: model.turnOverrides.agentDefaults(for: agent).model?.id,
                            hasConversation: true, contextTokens: session?.contextTokensUsed,
                            contextWindow: session?.contextWindow)
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

    private var session: SessionInfo? { model.knownSession(for: sessionId, preferredAgent: agent) }

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
                model.objectWillChange.send()
                model.turnOverrides.setChatOverrides(current, for: sessionId)
            }
        )
    }
}
