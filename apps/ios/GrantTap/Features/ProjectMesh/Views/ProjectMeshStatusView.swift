import SwiftUI

struct ProjectMeshStatusView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var refreshing = false
    @State private var toast: String?
    @State private var towerReport: ProjectRepositoryGraph?

    private var currentSnapshot: ProjectMeshSnapshot {
        model.meshSnapshots[snapshot.projectId] ?? snapshot
    }

    var bindings: [ProjectBindingSummary] {
        ProjectMeshLogic.visibleBindings(currentSnapshot.bindings ?? []).sorted {
            $0.displayName == $1.displayName
                ? $0.bindingId < $1.bindingId : $0.displayName < $1.displayName
        }
    }

    var body: some View {
        let snapshot = currentSnapshot
        List {
            Section(L("Mesh")) {
                CompatLabeledContent(
                    L("Mode"), value: ProjectManagePresentation.meshSummary(snapshot)
                )
                CompatLabeledContent(L("Tasks"), value: "\(snapshot.tasks.count)")
                CompatLabeledContent(L("Executions"), value: "\(snapshot.executions.count)")
                CompatLabeledContent(L("Snapshot received"), value: ReportBuilder.stamp(snapshot.generatedAt))
                if snapshot.incomplete == true {
                    Text(L("This snapshot is incomplete; missing Tasks or events are not deletions."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section(L("Weavatrix architecture")) {
                let repositoryIds = Set(bindings.map(\.repositoryId)
                    + [snapshot.project.canonicalRepositoryId]).sorted()
                ForEach(repositoryIds, id: \.self) { repositoryId in
                    let report = ProjectHealthDiagnostics.graphReport(
                        for: repositoryId, snapshot: snapshot
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ProjectRepositories.repositoryLeaf(repositoryId))
                        if repositoryIds.filter({ ProjectRepositories.repositoryLeaf($0)
                            == ProjectRepositories.repositoryLeaf(repositoryId) }).count > 1 {
                            Text(repositoryId).font(.caption2).foregroundStyle(Theme.muted)
                        }
                        Text(graphDetail(report))
                            .font(.caption).foregroundStyle(report?.analysisStatus == "COMPLETE" ? Theme.muted : .orange)
                        if let report, report.analysisStatus != "UNAVAILABLE" {
                            Text("Weavatrix \(report.weavatrixVersion) · \(report.revision.prefix(12))")
                                .font(.caption2).foregroundStyle(Theme.muted)
                            if let map = report.codeMap, !map.files.isEmpty {
                                Text("\(map.files.count)/\(map.totalFiles) \(L("files")) · \(map.roads.count) \(L("relations"))")
                                    .font(.caption2).foregroundStyle(Theme.muted)
                                if map.truncated {
                                    Text(L("Partial map"))
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            if report.codeMap?.files.isEmpty == false {
                                Button {
                                    towerReport = report
                                } label: {
                                    Label(L("Open code towers full screen"),
                                          systemImage: "building.2.crop.circle")
                                }
                                .accessibilityIdentifier("health.code-towers.\(repositoryId)")
                            } else {
                                Text(L("Code towers have not been reported. Rebuild architecture on an updated computer."))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                Button {
                    refreshing = true
                    Task {
                        toast = await model.requestProjectGraphAnalysis(projectId: snapshot.projectId).message
                        refreshing = false
                    }
                } label: {
                    HStack {
                        Label(L("Build or refresh code towers"), systemImage: "arrow.clockwise")
                        if refreshing { ProgressView() }
                    }
                }
                .disabled(refreshing)
                .accessibilityIdentifier("health.code-towers.refresh")
                NavigationLink(L("Open graph and analysis status")) {
                    ProjectGraphView(snapshot: snapshot, model: model)
                }
            }
            Section(L("Policy and execution")) {
                if let policy = model.projectGovernance[snapshot.projectId] {
                    CompatLabeledContent(L("Reported policy revision"), value: "\(policy.revision)")
                    CompatLabeledContent(L("Enforcement"), value: policy.enforcement.rawValue)
                    if let ready = policy.strictReady {
                        CompatLabeledContent(L("Strict coverage"), value: ready ? L("Ready") : L("Incomplete"))
                    }
                } else {
                    Text(L("No Mesh policy status has been reported by a computer."))
                        .font(.caption).foregroundStyle(.orange)
                }
                if let pending = model.pendingProjectPolicyRevisions[snapshot.projectId] {
                    CompatLabeledContent(L("Pending policy revision"), value: "\(pending)")
                }
                let route = model.projectGovernance[snapshot.projectId]?.policy?.execution ?? snapshot.execution
                CompatLabeledContent(
                    L("New Task route"),
                    value: route?.targetEndpointId.map {
                        ProjectHealthDiagnostics.computerName(
                            $0, connections: model.connectionRegistry.connections
                        )
                    } ?? L("Choose a permitted computer")
                )
            }
            Section(L("Computers")) {
                let computers = ProjectHealthDiagnostics.computers(
                    snapshot, connections: model.connectionRegistry.connections
                )
                if computers.isEmpty {
                    Text(L("No computer has reported a Mesh binding or execution."))
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(computers) { computer in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(computer.name)
                        Text(computerDetail(computer))
                            .font(.caption).foregroundStyle(computer.available == false ? .orange : Theme.muted)
                    }
                }
            }
            Section(L("Cortex Loom")) {
                ForEach(ProjectHealthDiagnostics.computers(
                    snapshot, connections: model.connectionRegistry.connections
                )) { computer in
                    CompatLabeledContent(
                        computer.name,
                        value: computer.cortex.map { $0.enabled ? $0.state : L("Off") }
                            ?? L("No report")
                    )
                }
                NavigationLink(L("Open Cortex diagnostics")) {
                    ProjectCortexView(snapshot: snapshot, model: model)
                }
            }
            Section(L("Measurements")) {
                NavigationLink(L("Open Mesh statistics and usage")) {
                    ProjectMeshStatisticsView(snapshot: snapshot, model: model)
                }
                Text(L("Missing usage reports remain unknown; Health describes the state of Mesh bindings, policy, and libraries."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Section(L("Repository bindings")) {
                if bindings.isEmpty {
                    Text(L("No repository bindings reported."))
                        .foregroundColor(Theme.muted)
                } else {
                    ForEach(bindings) { binding in ProjectBindingRow(binding: binding, model: model) }
                }
            }
        }
        .pageNavigationTitle(L("Health"))
        .transientToast($toast)
        .task(id: snapshot.projectId) { await model.observeProjectInsights(projectId: snapshot.projectId) }
        .refreshable { await model.refreshProjectInsights(projectId: snapshot.projectId, requestRemote: true) }
        .fullScreenCover(item: $towerReport) { report in
            if let map = report.codeMap {
                ProjectTowersFullScreen(
                    report: report,
                    repositoryName: ProjectOtherSide.displayName(of: report.repositoryId,
                                                                 in: currentSnapshot),
                    map: map
                )
            }
        }
    }

    private func computerDetail(_ computer: ProjectHealthDiagnostics.Computer) -> String {
        let bindings = LPlural(
            computer.bindingCount, one: "%d repository binding", many: "%d repository bindings"
        )
        let state = computer.available.map { $0 ? L("Available") : L("Unavailable") }
            ?? L("Binding not reported")
        return "\(bindings) · \(state)"
    }

    private func graphDetail(_ report: ProjectRepositoryGraph?) -> String {
        guard let report else { return L("No architecture analysis reported for this repository.") }
        if report.analysisStatus == "UNAVAILABLE" {
            return report.analysisErrorCode ?? L("Analysis unavailable")
        }
        return "\(report.analysisStatus ?? L("Legacy report")) · \(report.totalNodes) components · \(report.totalRelations) relations"
    }

}
