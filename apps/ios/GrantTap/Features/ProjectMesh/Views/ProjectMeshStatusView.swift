import SwiftUI

/// Observe the selected Mesh, while unrelated application changes leave its list intact.
struct ProjectMeshStatusView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var presentationCache = ProjectHealthPresentationCache()
    @AppStorage("health.reportFilter") private var reportFilter = "all"
    @AppStorage("health.reportSort") private var reportSort = "problems"
    @AppStorage("health.showDiagnostics") private var showDiagnostics = false

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
        let connections = model.connectionRegistry.connections
        ProjectHealthList(snapshot: snapshot, model: model,
            health: presentationCache.value(for: snapshot, connections: connections),
            request: model.projectGraphRequests[snapshot.projectId],
            policy: model.projectGovernance[snapshot.projectId],
            pendingPolicy: model.pendingProjectPolicyRevisions[snapshot.projectId], connections: connections,
            options: .init(filter: reportFilter, sort: reportSort, diagnostics: showDiagnostics),
            reportFilter: $reportFilter, reportSort: $reportSort, showDiagnostics: $showDiagnostics)
            .equatable()
            .task(id: snapshot.projectId) { await model.observeProjectInsights(projectId: snapshot.projectId) }
    }
}

private struct ProjectHealthList: View, Equatable {
    let snapshot: ProjectMeshSnapshot
    let model: AppModel
    let health: ProjectHealthPresentation
    let request: ProjectGraphRequest?
    let policy: ProjectGovernanceProjection?
    let pendingPolicy: Int?
    let connections: [LinkedComputer]
    let options: ProjectHealthOptions.Selection
    @Binding var reportFilter: String
    @Binding var reportSort: String
    @Binding var showDiagnostics: Bool
    @State private var towerReport: ProjectRepositoryGraph?
    @State private var repositoryIssue: ProjectHealthPresentation.Repository?
    @State private var diagnosticsExpanded = false
    @State private var showOptions = false

    private var currentSnapshot: ProjectMeshSnapshot { snapshot }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.snapshot == rhs.snapshot && lhs.request == rhs.request
            && lhs.policy == rhs.policy && lhs.pendingPolicy == rhs.pendingPolicy
            && lhs.connections == rhs.connections
            && lhs.options == rhs.options
    }

    var body: some View {
        List {
            architectureSection
            Section(L("Repositories")) {
                let repositories = ProjectHealthOptions.repositories(health.repositories, filter: options.filter, sort: options.sort)
                if repositories.isEmpty {
                    Text(L("No repositories match these options.")).foregroundStyle(Theme.muted)
                    if options.filter != "all", !health.repositories.isEmpty {
                        Button(L("Show all repositories")) { reportFilter = "all" }
                            .accessibilityIdentifier("health.options.show-all")
                    }
                }
                ForEach(repositories) { repository in
                    if let report = repository.report, repository.usable,
                       report.codeMap?.files.isEmpty == false {
                        Button { towerReport = report } label: { ProjectHealthRepositoryRow(repository: repository) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("health.code-towers.\(repository.id)")
                    } else {
                        Button { repositoryIssue = repository } label: {
                            ProjectHealthRepositoryRow(repository: repository)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("health.repository-issue.\(repository.id)")
                    }
                }
            }
            Section(L("Computers")) {
                if health.computers.isEmpty {
                    Text(L("No computer has reported a Mesh binding or execution."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                ForEach(health.computers) { computer in
                    ProjectHealthComputerRow(computer: computer, lastSeen: connections
                        .first { $0.id == computer.id }?.lastCatalogAt)
                }
            }
            if options.diagnostics { Section {
                DisclosureGroup(L("Diagnostics"), isExpanded: $diagnosticsExpanded) {
                    ProjectHealthDetails(snapshot: snapshot, computers: health.computers, model: model)
                }
                .accessibilityIdentifier("health.diagnostics")
            } }
        }
        .pageNavigationTitle(L("Health"))
        .accessibilityIdentifier("health.scroll")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showOptions = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel(L("Health options")).accessibilityIdentifier("health.options")
            }
        }
        .sheet(isPresented: $showOptions) {
            ProjectHealthOptionsSheet(filter: $reportFilter, sort: $reportSort, diagnostics: $showDiagnostics)
        }
        .refreshable { _ = await model.requestProjectGraphAnalysis(projectId: snapshot.projectId) }
        .sheet(item: $repositoryIssue) { repository in
            ProjectHealthRepositoryDetails(repository: repository, snapshot: currentSnapshot, model: model)
        }
        .fullScreenCover(item: $towerReport) { report in
            if let map = report.codeMap {
                ProjectTowersFullScreen(report: report,
                    repositoryName: ProjectOtherSide.displayName(of: report.repositoryId, in: currentSnapshot), map: map)
            }
        }
    }
    private var architectureSection: some View {
        Section(L("Architecture")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: L("%d of %d reports available"), health.availableCount, health.repositories.count))
                        .font(.headline)

                }
                .accessibilityIdentifier("health.architecture.summary")
                Text(health.errorCount == 0
                     ? String(format: L("%d current · %d saved"), health.currentCount, health.savedCount)
                     : String(format: L("%d current · %d saved · %d errors"),
                        health.currentCount, health.savedCount, health.errorCount))
                    .font(.caption).foregroundStyle(Theme.muted)
                Text(L("Snapshot received") + " · " + ReportBuilder.stamp(snapshot.generatedAt))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ProjectGraphBuildCard(
                request: request,
                reports: health.reports, needsAnalysis: health.needsAnalysis,
                actionIdentifier: "health.code-towers.refresh", compact: true
            ) {
                Task { _ = await model.requestProjectGraphAnalysis(projectId: snapshot.projectId) }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            NavigationLink {
                ProjectGraphView(snapshot: snapshot, model: model)
            } label: {
                Label(L("Open graph and analysis status"), systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
    }
}
