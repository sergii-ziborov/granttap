import SwiftUI

struct ProjectComputerUsageRow: View {
    let usage: ProjectComputerUsage
    @ObservedObject var model: AppModel
    var work: [ProjectComputerWork.Item] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(displayName).lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: L("%d×"), usage.calls))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let line = ProjectComputerWork.line(work) {
                Text(line).font(.caption)
                    .foregroundStyle(work.first?.working == true ? Theme.ok : Theme.muted)
                    .lineLimit(2)
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            if usage.failures > 0 {
                Text(String(format: L("%d failed"), usage.failures))
                    .font(.caption).foregroundStyle(Theme.riskHigh)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        model.connectionRegistry.connections
            .first { $0.id == usage.endpointId }?.displayName ?? usage.endpointId
    }

    private var detail: String? {
        let parts = [
            usage.cpuTimeMs.map { CapabilityResourceFormat.duration($0) },
            usage.peakMemoryBytes.map { CapabilityResourceFormat.bytes($0) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct ProjectBindingRow: View {
    let binding: ProjectBindingSummary
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: binding.available ? "externaldrive.fill.badge.checkmark" : "externaldrive")
                .frame(width: 24).foregroundColor(binding.available ? Theme.ok : Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(binding.displayName.isEmpty ? binding.repositoryId : binding.displayName)
                Text(detail).font(.caption).foregroundColor(Theme.muted).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    var detail: String {
        let computer = model.connectionRegistry.connections
            .first(where: { $0.id == binding.endpointId })?.displayName
            ?? shortEndpoint(binding.endpointId)
        let revision = binding.revision.map { String($0.prefix(12)) }
        return [computer, revision].compactMap { $0 }.joined(separator: " · ")
    }

    func shortEndpoint(_ endpoint: String) -> String {
        endpoint.count <= 24 ? endpoint : "\(L("Computer")) \(endpoint.prefix(8))"
    }
}

struct ProjectHealthRepositoryRow: View {
    let repository: ProjectHealthPresentation.Repository

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: repository.ready ? "checkmark.circle" : repository.usable
                  ? "circle.lefthalf.filled" : "exclamationmark.circle")
                .foregroundStyle(repository.ready ? Theme.ok : repository.current ? Theme.muted : Theme.riskMed)
                .frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                if let disambiguation = repository.disambiguation {
                    Text(disambiguation).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Text(repository.statusTitle).font(.caption.weight(.medium))
                    .foregroundStyle(repository.ready ? Theme.ok : repository.current ? Theme.muted : Theme.riskMed)
                if let detail = repository.detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if repository.usable { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted) }
        }
        .frame(minHeight: 44, alignment: .leading).padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ProjectHealthComputerRow: View {
    let computer: ProjectHealthDiagnostics.Computer
    let lastSeen: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(computer.name)
            Text(LPlural(computer.bindingCount, one: "%d repository binding", many: "%d repository bindings"))
                .font(.caption).foregroundStyle(Theme.muted)
            Text(L(computer.available.map { $0 ? "Repositories available" : "Repository unavailable" }
                   ?? "Binding not reported"))
                .font(.caption).foregroundStyle(computer.available == false ? Theme.riskMed : Theme.muted)
            if let lastSeen, lastSeen > 0 {
                Text(L("Last computer report") + " · " + ReportBuilder.stamp(lastSeen))
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ProjectHealthRepositoryDetails: View {
    let repository: ProjectHealthPresentation.Repository
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(repository.statusTitle) {
                    Text(repository.id).font(.caption).textSelection(.enabled)
                    if let detail = repository.detail { Text(detail) }
                }
                if let report = repository.report {
                    Section(L("Report provenance")) {
                        CompatLabeledContent("Weavatrix", value: report.weavatrixVersion)
                        if let revision = report.sourceRevision {
                            CompatLabeledContent(L("Source revision"), value: String(revision.prefix(12)))
                        }
                        CompatLabeledContent(L("Report fingerprint"), value: String(report.revision.prefix(12)))
                    }
                }
                Section {
                    Button(L("Refresh architecture")) {
                        Task { _ = await model.requestProjectGraphAnalysis(projectId: snapshot.projectId) }
                        dismiss()
                    }
                    NavigationLink(L("Open graph and analysis status")) {
                        ProjectGraphView(snapshot: snapshot, model: model)
                    }
                }
            }
            .pageNavigationTitle(repository.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }
}

struct ProjectHealthDetails: View {
    let snapshot: ProjectMeshSnapshot
    let computers: [ProjectHealthDiagnostics.Computer]
    @ObservedObject var model: AppModel

    var body: some View {
        CompatLabeledContent(L("Mode"), value: ProjectManagePresentation.meshSummary(snapshot))
        CompatLabeledContent(L("Tasks"), value: "\(snapshot.tasks.count)")
        CompatLabeledContent(L("Executions"), value: "\(snapshot.executions.count)")
        CompatLabeledContent(L("Snapshot received"), value: ReportBuilder.stamp(snapshot.generatedAt))
        if snapshot.incomplete == true {
            Text(L("This snapshot is incomplete; missing Tasks or events are not deletions."))
                .font(.caption).foregroundStyle(Theme.riskMed)
        }
        if let policy = model.projectGovernance[snapshot.projectId] {
            CompatLabeledContent(L("Reported policy revision"), value: "\(policy.revision)")
            CompatLabeledContent(L("Enforcement"), value: policy.enforcement.rawValue)
            if let ready = policy.strictReady {
                CompatLabeledContent(L("Strict coverage"), value: ready ? L("Ready") : L("Incomplete"))
            }
        } else {
            Text(L("No Mesh policy status has been reported by a computer."))
                .font(.caption).foregroundStyle(Theme.muted)
        }
        if let pending = model.pendingProjectPolicyRevisions[snapshot.projectId] {
            CompatLabeledContent(L("Pending policy revision"), value: "\(pending)")
        }
        let route = model.projectGovernance[snapshot.projectId]?.policy?.execution ?? snapshot.execution
        CompatLabeledContent(L("New Task route"), value: route?.targetEndpointId.map {
            ProjectHealthDiagnostics.computerName($0, connections: model.connectionRegistry.connections)
        } ?? L("Choose a permitted computer"))
        ForEach(computers) { computer in
            CompatLabeledContent("Cortex Loom · \(computer.name)", value: computer.cortex.map {
                $0.enabled ? $0.state : L("Off")
            } ?? L("No report"))
        }
        NavigationLink(L("Open Cortex diagnostics")) { ProjectCortexView(snapshot: snapshot, model: model) }
        NavigationLink(L("Open Mesh statistics and usage")) {
            ProjectMeshStatisticsView(snapshot: snapshot, model: model)
        }
        Text(L("Missing usage reports remain unknown; Health describes the state of Mesh bindings, policy, and libraries."))
            .font(.caption).foregroundStyle(Theme.muted)
        ForEach(ProjectMeshLogic.visibleBindings(snapshot.bindings ?? []).sorted { $0.bindingId < $1.bindingId }) {
            ProjectBindingRow(binding: $0, model: model)
        }
    }
}
