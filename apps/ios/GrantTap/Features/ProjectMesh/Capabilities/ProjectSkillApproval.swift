import CryptoKit
import Foundation

enum ProjectSkillApproval {
    private static let providers = ["claude", "codex", "cursor"]
    private static let prefix = "granttap-approved-skill-"

    static func policy(
        current: ProjectPolicy?, draft: ProjectGovernanceDraft?,
        projectId: String, skill: ProjectSharedSkill,
        enforcement: ProjectEnforcementMode
    ) -> ProjectPolicy? {
        guard skill.state == "discovered", let endpoint = skill.endpointId,
              !endpoint.isEmpty, let digest = skill.digest,
              digest.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { return nil }
        var result = ProjectGovernanceLogic.updatedPolicy(
            current: current, projectId: projectId, enforcement: draft?.enforcement ?? enforcement,
            defaults: draft?.defaults ?? ProjectGovernanceLogic.defaultEffects(current),
            named: draft?.named ?? ProjectGovernanceLogic.namedEffects(current),
            createdBy: "granttap-phone"
        )
        result.rules.removeAll { rule in
            rule.ruleId.hasPrefix(prefix) && rule.selector.kind == .skill
                && rule.selector.displayName == skill.name
                && rule.conditions.endpointIds == [endpoint]
        }
        for provider in providers {
            let fingerprint = ProjectCapabilityFingerprint(
                kind: .skill, displayName: skill.name, provider: provider,
                origin: "project-skill", scriptHash: digest, confidence: .exact
            )
            for (suffix, match, effect) in [
                ("exact", ProjectFingerprintMatch.exact, ProjectPolicyEffect.allow),
                ("changed", ProjectFingerprintMatch.changedFrom, ProjectPolicyEffect.ask),
            ] {
                let identity = "\(projectId)\u{1f}\(endpoint)\u{1f}\(skill.name)\u{1f}\(provider)\u{1f}\(suffix)"
                let hash = SHA256.hash(data: Data(identity.utf8))
                    .map { String(format: "%02x", $0) }.joined()
                result.rules.append(ProjectPolicyRule(
                    ruleId: "\(prefix)\(hash)", projectId: projectId,
                    selector: ProjectPolicySelector(
                        kind: .skill, displayName: skill.name,
                        fingerprint: ProjectFingerprintPredicate(match: match, expected: fingerprint)
                    ), effect: effect,
                    conditions: ProjectPolicyConditions(endpointIds: [endpoint], providers: []),
                    revision: result.revision, createdBy: "granttap-phone"
                ))
            }
        }
        result.rules.sort { $0.ruleId < $1.ruleId }
        return result
    }
}

@MainActor
extension AppModel {
    @discardableResult
    func approveProjectSkillBundle(projectId: String, skill: ProjectSharedSkill) -> Bool {
        guard meshSnapshots[projectId]?.skills?.contains(skill) == true,
              let status = projectGovernance[projectId],
              pendingProjectPolicyRevisions[projectId] == nil,
              let policy = ProjectSkillApproval.policy(
                current: status.policy, draft: projectPolicyDrafts[projectId],
                projectId: projectId, skill: skill, enforcement: status.enforcement
              ) else {
            projectPolicyErrors[projectId] = L("A reported exact skill bundle and Mesh policy are required.")
            return false
        }
        return submitProjectPolicy(policy, replacing: status.policy)
    }
}
