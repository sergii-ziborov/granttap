import SwiftUI

/// In-app Mesh statistics for one Project — the same facts a PDF report
/// exports, kept on the phone so they do not have to leave as a file.
struct ProjectMeshStatsView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var showReport = false

    private var report: ProjectReport {
        model.report(for: .project(snapshot))
    }

    private var sessionIds: Set<String> {
        ProjectUsageStats.sessionIds(snapshot)
    }

    private var events: [CapabilityUsageEvent] {
        ProjectUsageStats.events(CapabilityUsageStore.shared.events, snapshot: snapshot)
    }

    private var computers: [ProjectComputerUsage] {
        ProjectUsageStats.inventory(events, snapshot: snapshot)
            .filter { model.computerDisposition($0.endpointId, projectId: snapshot.projectId) != .removed }
    }

    private var activeComputerCount: Int {
        ProjectComputerRoster.hostIds(
            snapshot: snapshot,
            participating: model.computerRooms(for: snapshot.projectId),
            archived: model.archivedComputers(for: snapshot.projectId),
            removed: model.removedComputers(for: snapshot.projectId)
        ).count
    }

    var body: some View {
        List {
            Section {
                ForEach(report.figures) { figure in
                    VStack(alignment: .leading, spacing: 2) {
                        CompatLabeledContent(figure.label, value: figure.value)
                        if let note = figure.note {
                            Text(note).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                CompatLabeledContent(L("Active computers"), value: "\(activeComputerCount)")
                if !model.archivedComputers(for: snapshot.projectId).isEmpty {
                    CompatLabeledContent(
                        L("Archived computers"),
                        value: "\(model.archivedComputers(for: snapshot.projectId).count)"
                    )
                }
                CompatLabeledContent(L("Tasks"), value: "\(snapshot.tasks.count)")
                CompatLabeledContent(
                    L("Open executions"),
                    value: "\(snapshot.executions.filter { $0.endedAt == nil }.count)"
                )
                CompatLabeledContent(
                    L("Working tasks"),
                    value: "\(ProjectMeshStatsPresentation.taskCount(snapshot, state: "working"))"
                )
                CompatLabeledContent(
                    L("Blocked tasks"),
                    value: "\(ProjectMeshStatsPresentation.taskCount(snapshot, state: "blocked"))"
                )
            } header: {
                Text(L("This Project"))
            } footer: {
                Text(report.periodLine)
            }

            Section(L("Load by computer")) {
                if computers.isEmpty {
                    Text(L("No computers reported yet."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(computers) { row in
                    NavigationLink {
                        ProjectComputerUsageView(
                            endpointId: row.endpointId, snapshot: snapshot, model: model
                        )
                    } label: {
                        ProjectComputerUsageRow(
                            usage: row, model: model,
                            work: ProjectComputerWork.current(
                                snapshot: snapshot, endpointId: row.endpointId, sessions: model.sessions
                            )
                        )
                    }
                    .accessibilityIdentifier("mesh.stats.computer.\(row.endpointId)")
                }
            }

            let now = Date().timeIntervalSince1970 * 1_000
            let buckets = UsageTimeline.buckets(
                events, since: now - 24 * 3_600_000, until: now
            )
            if !buckets.isEmpty {
                Section {
                    UsageTimelineChart(buckets: buckets, accent: Theme.accent(for: "claude"))
                } header: {
                    Text(L("Last 24 hours"))
                } footer: {
                    Text(L("Calls over time across every computer in this Project."))
                }
            }

            Section {
                Button(L("Export PDF or CSV")) {
                    showReport = true
                }
                .accessibilityIdentifier("project.stats.export")
            } footer: {
                Text(L("A file to hand to someone else. The numbers above stay in Mesh."))
            }
        }
        .navigationTitle(L("Statistics"))
        .sheet(isPresented: $showReport) {
            ReportExportSheet(report: report)
        }
    }
}
