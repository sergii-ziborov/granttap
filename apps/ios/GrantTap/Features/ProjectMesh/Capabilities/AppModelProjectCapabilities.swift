import Foundation

@MainActor
extension AppModel {
    /// Capability choices belong to Project Governance, not a native session ID.
    @discardableResult
    func setProjectCapabilityEffect(
        projectId: String, kind: ProjectCapabilityKind,
        name: String, effect: ProjectPolicyEffect
    ) -> Bool {
        guard meshSnapshots[projectId] != nil,
              pendingProjectPolicyRevisions[projectId] == nil else {
            projectPolicyErrors[projectId] = L("Refresh Mesh policy before editing.")
            return false
        }
        let status = projectGovernance[projectId]
        let draft = projectPolicyDrafts[projectId]
        var named = draft?.named ?? ProjectGovernanceLogic.namedEffects(status?.policy)
        named[.init(kind: kind, name: name)] = effect
        return applyProjectGovernance(
            projectId: projectId,
            enforcement: draft?.enforcement ?? status?.enforcement ?? .bestAvailable,
            defaults: draft?.defaults ?? ProjectGovernanceLogic.defaultEffects(status?.policy),
            named: named
        )
    }
}
