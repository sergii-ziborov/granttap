import Foundation

enum ProjectAuxiliaryPolicyValidation {
    static func valid(
        _ execution: ProjectExecutionPolicy?, restrictions: ProjectRestrictionSet?,
        environment: ProjectEnvironment?, projectId: String,
        policyRevision: Int? = nil
    ) -> Bool {
        if let execution {
            guard ["distributed", "pinned"].contains(execution.mode),
                  execution.mode != "pinned" || execution.targetEndpointId != nil,
                  execution.defaultProvider.map(AgentIdentity.knownIds.contains) ?? true,
                  (execution.defaultModel?.count ?? 0) <= 160,
                  execution.revision > 0,
                  policyRevision.map({ execution.revision <= $0 }) ?? true,
                  ["none", "pending", "applied", "unavailable"].contains(execution.hostGrantStatus),
                  ["reject", "queueUntilDeadline"].contains(execution.offlineBehavior)
            else { return false }
        }
        if let restrictions {
            guard restrictions.projectId == projectId,
                  restrictions.revision > 0,
                  policyRevision.map({ restrictions.revision <= $0 }) ?? true,
                  ["project", "project_and_repo", "sync_from_repo"].contains(restrictions.scope),
                  restrictions.rules.count <= 32,
                  Set(restrictions.rules.map(\.ruleId)).count == restrictions.rules.count,
                  restrictions.rules.allSatisfy({ rule in
                      ["max_file_lines", "max_function_lines", "max_file_bytes", "custom"]
                          .contains(rule.kind) && (rule.kind == "custom" ? rule.name != nil : rule.limit != nil)
                          && ["ask", "deny"].contains(rule.effect)
                          && (rule.paths?.count ?? 0) <= 16
                  }) else { return false }
        }
        if let environment {
            guard environment.projectId == projectId,
                  environment.revision > 0,
                  policyRevision.map({ environment.revision <= $0 }) ?? true,
                  environment.variables.count <= 64,
                  Set(environment.variables.map(\.key)).count == environment.variables.count,
                  environment.variables.allSatisfy({
                      ProjectEnvironmentKey.allowed($0.key) && ($0.value?.count ?? 0) <= 4_096
                  })
            else { return false }
        }
        return true
    }
}
