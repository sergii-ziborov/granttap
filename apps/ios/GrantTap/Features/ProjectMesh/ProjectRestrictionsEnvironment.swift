import Foundation
import SwiftUI

enum ProjectRestrictionsPresentation {
    static let recommended: [ProjectRestrictionRule] = [
        ProjectRestrictionRule(
            ruleId: "max-file-lines", kind: .maxFileLines, limit: 500, effect: .deny
        ),
        ProjectRestrictionRule(
            ruleId: "max-function-lines", kind: .maxFunctionLines, limit: 100, effect: .deny
        ),
        ProjectRestrictionRule(
            ruleId: "max-file-bytes", kind: .maxFileBytes, limit: 65_536, effect: .deny
        ),
    ]

    static func summary(
        _ snapshot: ProjectMeshSnapshot, governance: ProjectGovernanceProjection?
    ) -> String {
        let set = snapshot.restrictions ?? governance?.policy?.restrictions
        guard let set, !set.rules.isEmpty else { return L("No restrictions") }
        let count = set.rules.count
        let rules = String(format: L(count == 1 ? "%d rule" : "%d rules"), count)
        return "\(rules) · \(scopeLabel(set.scope))"
    }

    static func scopeLabel(_ scope: ProjectRestrictionScope) -> String {
        switch scope {
        case .project: return L("This Project")
        case .projectAndRepo: return L("Project and repository")
        case .syncFromRepo: return L("Sync from repository")
        }
    }

    static func kindLabel(_ kind: ProjectRestrictionKind) -> String {
        switch kind {
        case .maxFileLines: return L("File line limit")
        case .maxFunctionLines: return L("Method line limit")
        case .maxFileBytes: return L("File size limit")
        case .custom: return L("Custom")
        }
    }

    static func ruleDetail(_ rule: ProjectRestrictionRule) -> String {
        let effect = rule.effect == .ask ? L("Ask") : L("Deny")
        if rule.kind == .custom {
            return "\(rule.name ?? L("Custom")) · \(effect)"
        }
        let limit = rule.limit.map { "\($0)" } ?? "—"
        return "\(limit) · \(effect)"
    }
}

enum ProjectEnvironmentLogic {
    static func mergingSecrets(
        current: ProjectEnvironment?, incoming: ProjectEnvironment?
    ) -> ProjectEnvironment? {
        guard let incoming else { return current }
        let kept = Dictionary(uniqueKeysWithValues: (current?.variables ?? []).map { ($0.key, $0) })
        return ProjectEnvironment(
            projectId: incoming.projectId,
            revision: incoming.revision,
            shareNonSecretsWithRepo: incoming.shareNonSecretsWithRepo,
            variables: incoming.variables.map { item in
                if item.value != nil { return item }
                if let previous = kept[item.key], previous.value != nil {
                    return ProjectEnvVar(key: item.key, value: previous.value, secret: item.secret)
                }
                return item
            }
        )
    }
}

enum ProjectEnvironmentPresentation {
    static func summary(
        _ snapshot: ProjectMeshSnapshot, governance: ProjectGovernanceProjection?
    ) -> String {
        let environment = snapshot.environment ?? governance?.policy?.environment
        guard let environment, !environment.variables.isEmpty else { return L("No variables") }
        let secrets = environment.variables.filter(\.secret).count
        let count = environment.variables.count
        var parts = [String(format: L(count == 1 ? "%d variable" : "%d variables"), count)]
        if secrets > 0 {
            parts.append(String(format: L(secrets == 1 ? "%d secret" : "%d secrets"), secrets))
        }
        if environment.shareNonSecretsWithRepo { parts.append(L("shared with the repository")) }
        return parts.joined(separator: " · ")
    }

    static func isValidKey(_ key: String) -> Bool {
        key.range(of: "^[A-Z][A-Z0-9_]{0,127}$", options: .regularExpression) != nil
    }
}
