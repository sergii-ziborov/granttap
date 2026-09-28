import SwiftUI

struct ProjectCapabilityRequestDetailView: View {
    let request: ProjectCapabilityRequest
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var expired: Bool {
        Date().timeIntervalSince1970 * 1_000 - request.requestedAt >= 24 * 60 * 60 * 1_000
    }

    private var current: ProjectMeshSnapshot {
        model.meshSnapshots[request.projectId] ?? snapshot
    }

    private var reports: [ProjectCapabilityObservation] {
        (current.capabilityObservations ?? [])
            .filter { $0.requestId == request.requestId && $0.projectId == request.projectId }
            .sorted { $0.endpointId < $1.endpointId }
    }

    private var computers: [String] {
        if let target = request.targetEndpointId { return [target] }
        return Array(Set((current.bindings ?? []).map(\.endpointId)
            + current.executions.map(\.computerId))).sorted()
    }

    private var approvedSkills: [ProjectSharedSkill] {
        (current.skills ?? []).filter { skill in
            request.kind == .skill && skill.name.caseInsensitiveCompare(request.name) == .orderedSame
                && skill.state == "discovered" && skill.digest != nil
                && (request.artifactDigest == nil || request.artifactDigest == skill.digest)
                && (request.targetEndpointId == nil || request.targetEndpointId == skill.endpointId)
        }
    }

    var body: some View {
        List {
            Section(L("Mesh request")) {
                CompatLabeledContent(L("Capability"), value: request.name)
                CompatLabeledContent(L("Kind"), value: request.kind.title)
                if let version = request.version {
                    CompatLabeledContent(L("Requested version"), value: version)
                }
                if let source = request.source {
                    CompatLabeledContent(L("Source"), value: source)
                }
                if let digest = request.artifactDigest {
                    CompatLabeledContent(request.kind == .skill
                                         ? L("Bundle digest") : L("Native config digest"),
                                         value: String(digest.prefix(16)))
                }
                CompatLabeledContent(L("Route"), value:
                    request.targetEndpointId ?? L("All bound computers"))
                if expired { Text(L("Request expired; send it again to retry."))
                    .foregroundStyle(Theme.muted) }
            }
            Section {
                if computers.isEmpty {
                    Text(L("No computer is linked to this Mesh yet."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(computers, id: \.self) { endpoint in
                    let report = reports.first { $0.endpointId == endpoint }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ProjectHealthDiagnostics.computerName(
                            endpoint, connections: model.connectionRegistry.connections
                        ))
                        Text(report.map { Self.stateLabel($0.state) }
                             ?? L("No response for this request"))
                            .font(.caption).foregroundStyle(Theme.muted)
                        if let version = report?.version {
                            Text(String(format: L("Observed version %@"), version))
                                .font(.caption2).foregroundStyle(Theme.muted)
                        }
                        if let digest = report?.artifactDigest {
                            Text("\(L("Observed digest")) · \(String(digest.prefix(16)))")
                                .font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                }
            } header: {
                Text(L("Computer results"))
            } footer: {
                Text(L("Discovered and configured do not mean approved, installed for every provider, or used. An initialized MCP answered a metadata probe on the reporting computer."))
            }
            Section(L("Governance")) {
                if let policy = model.projectGovernance[request.projectId] {
                    let matching = policy.policy?.rules.filter { rule in
                        rule.selector.kind?.rawValue == request.kind.rawValue
                            && rule.selector.displayName?.caseInsensitiveCompare(request.name) == .orderedSame
                    } ?? []
                    Text(matching.isEmpty
                         ? L("No capability rule has been applied for this name.")
                         : String(format: L("%d Mesh rules at revision %d"),
                                  matching.count, policy.revision))
                    if model.pendingProjectPolicyRevisions[request.projectId] != nil {
                        Text(L("Waiting for computer policy confirmation"))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(policy.coverage.filter {
                        $0.capability == request.kind.rawValue
                            && computers.contains($0.endpointId)
                    }) { row in
                        CompatLabeledContent("\(row.endpointId) · \(row.provider)",
                                             value: row.status.rawValue)
                    }
                } else {
                    Text(L("Mesh policy has not been reported."))
                        .foregroundStyle(Theme.muted)
                }
                if let error = model.projectPolicyErrors[request.projectId] {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section(L("Actions")) {
                ForEach(approvedSkills) { skill in
                    Button(String(format: L("Approve exact bundle on %@"), skill.endpointId ?? "")) {
                        model.approveProjectSkillBundle(projectId: request.projectId, skill: skill)
                    }
                }
                Button(L("Require approval for this name")) {
                    model.setProjectCapabilityEffect(
                        projectId: request.projectId,
                        kind: request.kind == .skill ? .skill : .mcp,
                        name: request.name, effect: .ask
                    )
                }
                Button(L("Deny this name")) {
                    model.setProjectCapabilityEffect(
                        projectId: request.projectId,
                        kind: request.kind == .skill ? .skill : .mcp,
                        name: request.name, effect: .deny
                    )
                }
            }
            .disabled(model.projectGovernance[request.projectId] == nil
                      || model.pendingProjectPolicyRevisions[request.projectId] != nil)
            if expired {
                Section {
                    Button(L("Send request again")) {
                        model.requestProjectCapability(
                            projectId: request.projectId, kind: request.kind,
                            name: request.name, source: request.source, version: request.version,
                            artifactDigest: request.artifactDigest,
                            targetEndpointId: request.targetEndpointId
                        )
                        dismiss()
                    }
                }
            }
        }
        .pageNavigationTitle(request.name)
    }

    static func stateLabel(_ state: String) -> String {
        switch state {
        case "needs_binding": return L("Needs a local Mesh binding")
        case "not_found": return L("Not found in native configuration")
        case "discovered": return L("Skill bundle discovered")
        case "configured": return L("MCP configured; initialization not confirmed")
        case "initialized": return L("MCP initialized on this computer")
        case "credential_missing": return L("Credentials missing")
        case "version_conflict": return L("Version or bundle conflict")
        case "unsupported": return L("Unsupported or disabled here")
        default: return L("Unknown result")
        }
    }
}
