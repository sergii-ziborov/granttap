import SwiftUI

/// Policy is edited in details so the list keeps one full-width navigation target.
struct ProjectCapabilityPolicyMenu: View {
    let info: ProjectCapabilityInfo
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var body: some View {
        let kind: ProjectCapabilityKind = info.kind == .skill ? .skill : .mcp
        let rule = ProjectGovernanceLogic.NamedRule(kind: kind, name: info.name)
        let projection = model.projectGovernance[snapshot.projectId]
        let effect = model.projectPolicyDrafts[snapshot.projectId]?.named[rule]
            ?? ProjectGovernanceLogic.namedEffects(projection?.policy)[rule]
        Menu {
            ForEach([ProjectPolicyEffect.ask, .deny], id: \.self) { choice in
                Button(ProjectGovernancePresentation.effectLabel(choice)) {
                    model.setProjectCapabilityEffect(projectId: snapshot.projectId, kind: kind,
                        name: info.name, effect: choice)
                }
            }
            if let skill = snapshot.skills?.first(where: {
                $0.name == info.name && $0.endpointId == info.endpointId
            }), skill.digest != nil, skill.endpointId != nil, skill.state == "discovered" {
                Button(L("Approve exact bundle")) {
                    model.approveProjectSkillBundle(projectId: snapshot.projectId, skill: skill)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .accessibilityLabel(L("Mesh rule"))
        }
        .accessibilityValue(effect.map(ProjectGovernancePresentation.effectLabel) ?? L("No override"))
        .accessibilityIdentifier("project.capability.policy")
        .disabled(model.demoMode || model.pendingProjectPolicyRevisions[snapshot.projectId] != nil)
    }
}
