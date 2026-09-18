import Foundation

enum ProjectPolicyEffect: String, Codable, CaseIterable {
    case allow
    case ask
    case deny

    var severity: Int {
        switch self {
        case .deny: return 3
        case .ask: return 2
        case .allow: return 1
        }
    }
}

enum ProjectEnforcementMode: String, Codable, CaseIterable {
    case bestAvailable = "best_available"
    case strict
}

enum ProjectPolicyCoverageStatus: String, Codable, CaseIterable {
    case enforced
    case observed
    case unsupported
    case unknown

    var rank: Int {
        switch self {
        case .enforced: return 0
        case .observed: return 1
        case .unsupported: return 2
        case .unknown: return 3
        }
    }
}

struct ProjectPolicyRuleSummary: Codable, Equatable, Identifiable {
    let ruleId: String
    let effect: ProjectPolicyEffect
    let capabilityKind: String
    var displayName: String? = nil
    var provider: String? = nil
    var origin: String? = nil
    var fingerprintConfidence: String? = nil
    var id: String { ruleId }
}

struct ProjectPolicyCoverageSummary: Codable, Equatable, Identifiable {
    let endpointId: String
    let provider: String
    let capability: String
    let status: ProjectPolicyCoverageStatus
    var policyRevision: Int? = nil
    var id: String { "\(endpointId)\u{1f}\(provider)\u{1f}\(capability)" }
}

struct ProjectGovernanceProjection: Codable, Equatable, Identifiable {
    let projectId: String
    let revision: Int
    let enforcement: ProjectEnforcementMode
    let rules: [ProjectPolicyRuleSummary]
    let coverage: [ProjectPolicyCoverageSummary]
    let updatedAt: Double
    var requiredCapabilities: [ProjectCapabilityKind]? = nil
    var strictReady: Bool? = nil
    var policy: ProjectPolicy? = nil
    var id: String { projectId }
}

struct ProjectComputerSummary: Equatable, Identifiable {
    let endpointId: String
    let displayName: String
    let repositoryCount: Int
    let available: Bool
    var id: String { endpointId }
    var detail: String {
        let repositories = String(
            format: L(repositoryCount == 1 ? "%d repository" : "%d repositories"),
            repositoryCount
        )
        return "\(repositories) · \(L(available ? "Available" : "Unavailable"))"
    }
}

enum ProjectManagePresentation {
    /// How many rules this Project has: what the person chose on the phone
    /// (a draft still on its way counts), else the policy the computers
    /// acknowledged, else the summaries the status carried. The status summary
    /// lists named rules only, so it said "0 rules" over a chosen default.
    static func governanceSummary(
        _ governance: ProjectGovernanceProjection?, draft: ProjectGovernanceDraft? = nil
    ) -> String {
        let configured: Int? = draft.map { $0.defaults.count + $0.named.count }
            ?? governance.map { $0.policy?.rules.count ?? $0.rules.count }
        guard let configured else { return L("Not reported") }
        if configured == 0 { return L("No rules yet") }
        return String(format: L(configured == 1 ? "%d rule" : "%d rules"), configured)
    }

    static func membersSummary(_ snapshot: ProjectMeshSnapshot) -> String {
        let count = endpointIds(snapshot).count
        let computers = String(
            format: L(count == 1 ? "%d computer" : "%d computers"), count
        )
        return "\(L("1 person")) · \(computers)"
    }

    static func meshSummary(_ snapshot: ProjectMeshSnapshot) -> String {
        let count = endpointIds(snapshot).count
        let computers = String(
            format: L(count == 1 ? "%d computer" : "%d computers"), count
        )
        return "\(L(count > 1 ? "Shared" : "Private")) · \(computers)"
    }

    /// Compact Health / Graph line: Mesh mode, then usage only when the phone
    /// already holds calls for this Project. Missing usage is omitted, never
    /// described as a graph of unused capacity.
    static func healthSummary(
        _ snapshot: ProjectMeshSnapshot, usageEvents: [CapabilityUsageEvent] = []
    ) -> String {
        let mesh = meshSummary(snapshot)
        let events = ProjectUsageStats.events(usageEvents, snapshot: snapshot)
        guard !events.isEmpty else { return mesh }
        return "\(mesh) · \(String(format: L(events.count == 1 ? "%d call" : "%d calls"), events.count))"
    }

    /// Working section detail: open tasks and executors still alive.
    static func workingSummary(_ snapshot: ProjectMeshSnapshot) -> String {
        let openTasks = snapshot.tasks.filter { !["completed", "failed"].contains($0.state) }.count
        let executors = snapshot.executions.filter { $0.endedAt == nil }.count
        let tasks = String(format: L(openTasks == 1 ? "%d task" : "%d tasks"), openTasks)
        let running = String(format: L(executors == 1 ? "%d executor" : "%d executors"), executors)
        return "\(tasks) · \(running)"
    }

    /// The computers actually taking part in this Project.
    ///
    /// A computer counts when it has reported a repository for the Project, or
    /// when it has an execution open right now. A closed execution is not
    /// enough: macOS renames a Mac with the network it joins, so every former
    /// name of one machine left executions behind for good and was counted as
    /// another computer — "2 computers" for a Project with one, the second
    /// carrying no repositories because it never bound any.
    /// An execution is only open while its computer is still saying so.
    ///
    /// Nothing closes an execution belonging to a computer that stopped
    /// reporting — the sweep only covers the machine publishing the snapshot.
    /// A Mac renamed by its network therefore left an execution open under its
    /// former name for good. A computer that is really working republishes
    /// every half minute, so silence this long is abandonment.
    static let abandonedExecutionMs: Double = 10 * 60 * 1_000

    static func endpointIds(_ snapshot: ProjectMeshSnapshot) -> [String] {
        let bound = snapshot.bindings?.map(\.endpointId) ?? []
        let working = snapshot.executions.filter { execution in
            execution.endedAt == nil
                && snapshot.generatedAt - (execution.updatedAt ?? execution.startedAt)
                    <= abandonedExecutionMs
        }.map(\.computerId)
        let known = Set(bound + working)
        if !known.isEmpty { return known.sorted() }
        // Nothing bound and nothing open: fall back to whoever ever ran here,
        // so a Project seen only in history still names its machine.
        return Array(Set(snapshot.executions.map(\.computerId))).sorted()
    }
}
