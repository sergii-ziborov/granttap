import SwiftUI

/// Write one Project rule from the place the need for it appears.
///
/// Governance lived only on its own screen, and nobody starts a policy from an
/// empty screen. The moment a person wants a rule is when they are looking at
/// the thing — a tool in Usage, a server on the Project page — so the rule is
/// offered there, as one choice, and the rest of the policy is left as it was.
enum ProjectGovernanceQuickRule {
    /// The Project a set of chats belongs to, when they agree on one.
    ///
    /// Chats from two Projects have no single policy to write into, and a rule
    /// must never land in a Project the person was not looking at.
    @MainActor
    static func projectId(for sessionIds: Set<String>, in model: AppModel) -> String? {
        let ids = Set((model.sessions + model.allSessionHistory)
            .filter { sessionIds.contains($0.sessionId) }
            .compactMap(\.projectId))
        return ids.count == 1 ? ids.first : nil
    }

    /// Apply one named rule on top of the Project's current policy.
    @MainActor
    static func apply(
        _ effect: ProjectPolicyEffect?, to kind: CapabilityUsageKind, named name: String,
        projectId: String, model: AppModel
    ) -> String {
        guard let governed = ProjectGovernanceCandidates.governedKind(kind) else {
            return L("This kind of capability is not governed per Project.")
        }
        let current = model.projectGovernance[projectId]
        var named = ProjectGovernanceLogic.namedEffects(current?.policy)
        let rule = ProjectGovernanceLogic.NamedRule(kind: governed, name: name)
        if let effect { named[rule] = effect } else { named.removeValue(forKey: rule) }
        let saved = model.applyProjectGovernance(
            projectId: projectId,
            enforcement: current?.enforcement ?? .bestAvailable,
            defaults: ProjectGovernanceLogic.defaultEffects(current?.policy),
            named: named
        )
        if saved {
            return effect.map { String(format: L("%@ for this Project: %@."), name,
                                       ProjectGovernancePresentation.effectLabel($0)) }
                ?? String(format: L("%@ now follows its kind."), name)
        }
        return model.projectPolicyErrors[projectId] ?? L("Policy could not be saved.")
    }
}

/// The three effects and "inherit", as a menu a row can carry.
struct ProjectGovernanceQuickMenu: View {
    let kind: CapabilityUsageKind
    let name: String
    let projectId: String
    @ObservedObject var model: AppModel
    @Binding var toast: String?

    private var current: ProjectPolicyEffect? {
        guard let governed = ProjectGovernanceCandidates.governedKind(kind) else { return nil }
        return ProjectGovernanceLogic.namedEffects(model.projectGovernance[projectId]?.policy)[
            .init(kind: governed, name: name)
        ]
    }

    var body: some View {
        Menu {
            ForEach(ProjectPolicyEffect.allCases, id: \.self) { effect in
                Button {
                    toast = ProjectGovernanceQuickRule.apply(
                        effect, to: kind, named: name, projectId: projectId, model: model
                    )
                } label: {
                    Label(
                        ProjectGovernancePresentation.effectLabel(effect),
                        systemImage: current == effect ? "checkmark" : icon(effect)
                    )
                }
            }
            if current != nil {
                Button {
                    toast = ProjectGovernanceQuickRule.apply(
                        nil, to: kind, named: name, projectId: projectId, model: model
                    )
                } label: {
                    Label(L("Inherit from kind"), systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Label(L("Governance"), systemImage: "checkmark.shield")
        }
        .accessibilityIdentifier("governance.quick.\(kind.rawValue).\(name)")
    }

    private func icon(_ effect: ProjectPolicyEffect) -> String {
        switch effect {
        case .allow: return "checkmark.circle"
        case .ask: return "questionmark.circle"
        case .deny: return "xmark.circle"
        }
    }
}
