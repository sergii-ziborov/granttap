import Foundation

@MainActor
extension AppModel {
    @discardableResult
    func applyProjectRestrictions(
        projectId: String, scope: String, rules: [ProjectRestrictionRule]
    ) -> Bool {
        guard ["project", "project_and_repo", "sync_from_repo"].contains(scope),
              let projection = projectGovernance[projectId] else { return false }
        let current = projection.policy
        let revision = (current?.revision ?? 0) + 1
        var policyRules = current?.rules ?? []
        for index in policyRules.indices { policyRules[index].revision = revision }
        let restrictions = ProjectRestrictionSet(
            projectId: projectId, revision: revision, scope: scope,
            repositoryId: meshSnapshots[projectId]?.project.canonicalRepositoryId,
            rules: rules, source: scope == "sync_from_repo" ? "repo" : "phone"
        )
        return submitProjectPolicy(ProjectPolicy(
            projectId: projectId, revision: revision,
            enforcement: current?.enforcement ?? .bestAvailable, rules: policyRules,
            execution: current?.execution, restrictions: restrictions,
            environment: current?.environment
        ), replacing: current)
    }

    @discardableResult
    func applyProjectEnvironment(
        projectId: String, shareNonSecrets: Bool,
        variables: [ProjectEnvironmentVariable]
    ) -> Bool {
        guard let projection = projectGovernance[projectId] else { return false }
        let current = projection.policy
        let revision = (current?.revision ?? 0) + 1
        var policyRules = current?.rules ?? []
        for index in policyRules.indices { policyRules[index].revision = revision }
        let environment = ProjectEnvironment(
            projectId: projectId, revision: revision,
            shareNonSecretsWithRepo: shareNonSecrets, variables: variables
        )
        return submitProjectPolicy(ProjectPolicy(
            projectId: projectId, revision: revision,
            enforcement: current?.enforcement ?? .bestAvailable, rules: policyRules,
            execution: current?.execution, restrictions: current?.restrictions,
            environment: environment
        ), replacing: current)
    }
}
