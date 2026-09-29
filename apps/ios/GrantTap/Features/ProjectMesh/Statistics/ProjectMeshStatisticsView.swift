import SwiftUI

struct ProjectMeshStatisticsView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @ObservedObject private var usage: CapabilityUsageStore

    init(snapshot: ProjectMeshSnapshot, model: AppModel, usage: CapabilityUsageStore? = nil) {
        self.snapshot = snapshot
        self.model = model
        self.usage = usage ?? .shared
    }

    private var currentSnapshot: ProjectMeshSnapshot {
        ProjectMeshStatistics.presented(model.meshSnapshots[snapshot.projectId] ?? snapshot,
                                        sessions: model.sessions + model.allSessionHistory)
    }

    private var events: [CapabilityUsageEvent] {
        ProjectUsageStats.events(usage.events, snapshot: currentSnapshot,
                                 roomByEndpointId: model.projectUsageRooms)
    }

    private var totals: (calls: Int, failures: Int, peakMemoryBytes: Int?, cpuTimeMs: Int?)? {
        ProjectUsageStats.totals(events)
    }

    var body: some View {
        let snapshot = currentSnapshot
        let value = ProjectMeshStatistics.make(snapshot)
        let hasGraph = ProjectInsightReports.hasEvidence(snapshot)
        let live = ProjectLiveResources.samples(
            snapshot: snapshot, roomByEndpointId: model.projectUsageRooms,
            loadsByRoom: model.machineLoadByRoom,
            nowMs: Date().timeIntervalSince1970 * 1_000
        )
        let host = ProjectLiveResources.hostSamples(
            snapshot: snapshot, roomByEndpointId: model.projectUsageRooms,
            loadsByRoom: model.machineLoadByRoom,
            nowMs: Date().timeIntervalSince1970 * 1_000
        )
        List {
            Section(L("Tasks by state")) {
                NavigationLink {
                    ProjectStatisticsTasksView(snapshot: snapshot, model: model)
                } label: {
                    ProjectTaskStateDiagram(tasks: snapshot.tasks)
                }
                .accessibilityIdentifier("statistics.tasks.chart")
            }
            Section(L("Activity and evidence")) {
                NavigationLink {
                    ProjectStatisticsActivityView(snapshot: snapshot, model: model)
                } label: {
                    ProjectStatisticBars(values: [
                        .init(label: L("Tasks"), count: value.tasks, color: .blue),
                        .init(label: L("Executions"), count: value.executions, color: .teal),
                        .init(label: L("Mesh events in snapshot"), count: value.events, color: .orange),
                    ])
                }
                .accessibilityIdentifier("statistics.activity.chart")
                if !hasGraph {
                    Text(L("Graph evidence has not been reported; its count is unknown."))
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(L("Counts describe this bounded Mesh snapshot. Missing history and telemetry are not zero activity."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Section(L("Tokens and resources")) {
                NavigationLink {
                    ProjectStatisticsUsageView(snapshot: snapshot, model: model)
                } label: {
                    CompatLabeledContent(L("Tokens"), value: ProjectUsageStats.reportedTokens(
                        model.sessions + model.allSessionHistory, snapshot: snapshot
                    ).map(Format.tokens) ?? L("Not reported"))
                }
                NavigationLink {
                    ProjectStatisticsUsageView(snapshot: snapshot, model: model)
                } label: {
                    CompatLabeledContent(L("Tool calls"), value: totals.map { "\($0.calls)" }
                        ?? L("Not reported"))
                }
                NavigationLink {
                    ProjectStatisticsUsageView(snapshot: snapshot, model: model)
                } label: {
                    CompatLabeledContent(L("CPU time"), value: totals?.cpuTimeMs.map {
                        CapabilityResourceFormat.duration($0)
                    } ?? L("Not reported"))
                }
                NavigationLink {
                    ProjectStatisticsUsageView(snapshot: snapshot, model: model)
                } label: {
                    CompatLabeledContent(L("Peak memory"), value: totals?.peakMemoryBytes.map {
                        CapabilityResourceFormat.bytes($0)
                    } ?? L("Not reported"))
                }
                if !events.isEmpty {
                    NavigationLink {
                        ProjectStatisticsUsageView(snapshot: snapshot, model: model)
                    } label: {
                        UsageTimelineChart(
                            buckets: UsageTimeline.buckets(
                                events, since: Date().timeIntervalSince1970 * 1_000 - 86_400_000,
                                until: Date().timeIntervalSince1970 * 1_000
                            ),
                            accent: Theme.codex
                        )
                    }
                }
            }
            Section(L("Live execution processes")) {
                if live.isEmpty {
                    Text(L("No fresh process sample matches an active Mesh execution."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                ForEach(live) { sample in
                    NavigationLink {
                        ProjectComputerUsageView(
                            endpointId: sample.endpointId, snapshot: snapshot, model: model
                        )
                    } label: {
                        ProjectLiveResourceRow(sample: sample, name: computerName(sample.endpointId))
                    }
                }
            }
            if !host.isEmpty {
                Section(L("Host agent processes")) {
                    ForEach(host) { sample in
                        NavigationLink {
                            ProjectComputerUsageView(
                                endpointId: sample.endpointId, snapshot: snapshot, model: model
                            )
                        } label: {
                            ProjectHostAgentResourceRow(
                                sample: sample, computerName: computerName(sample.endpointId)
                            )
                        }
                    }
                    Text(L("Shared host load can include other Mesh spaces; it is not attributed to this Mesh."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Section(L("Work")) {
                workLink(L("Tasks"), count: value.tasks, snapshot: snapshot)
                workLink(L("Active tasks"), count: value.activeTasks, snapshot: snapshot)
                NavigationLink {
                    ProjectStatisticsActivityView(snapshot: snapshot, model: model)
                } label: {
                    CompatLabeledContent(L("Executions"), value: "\(value.executions)")
                }
                NavigationLink {
                    ProjectStatisticsActivityView(snapshot: snapshot, model: model)
                } label: {
                    CompatLabeledContent(L("Mesh events in snapshot"), value: "\(value.events)")
                }
            }
            Section(L("Graph")) {
                NavigationLink {
                    ProjectGraphView(snapshot: snapshot, model: model)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Open architecture graph"))
                        Text(graphSource(snapshot))
                            .font(.caption).foregroundStyle(Theme.muted)
                        if hasGraph {
                            Text(String(format: L("%d nodes · %d relations"),
                                        value.graphNodes, value.graphRelations))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            Section(L("Capabilities")) {
                NavigationLink {
                    ProjectCapabilitiesView(snapshot: snapshot, model: model)
                } label: {
                    CompatLabeledContent(L("Skills and MCP"),
                                         value: "\(value.skills) · \(value.mcpServers)")
                }
            }
            Section(L("Cortex Loom")) {
                NavigationLink {
                    ProjectCortexView(snapshot: snapshot, model: model)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Open context diagnostics"))
                        Text(String(format: L("%d reporting computers · %d prepared packets"),
                                    value.cortexEndpoints, value.cortexPackets))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .pageNavigationTitle(L("Statistics"))
        .task(id: snapshot.projectId) { await model.observeProjectInsights(projectId: snapshot.projectId) }
        .refreshable { await model.refreshProjectInsights(projectId: snapshot.projectId, requestRemote: true) }
    }

    private func workLink(
        _ title: String, count: Int, snapshot: ProjectMeshSnapshot
    ) -> some View {
        NavigationLink {
            ProjectStatisticsTasksView(snapshot: snapshot, model: model)
        } label: {
            CompatLabeledContent(title, value: "\(count)")
        }
    }

    private func graphSource(_ snapshot: ProjectMeshSnapshot) -> String {
        if let report = ProjectInsightReports.reports(snapshot).first {
            return "Weavatrix \(report.weavatrixVersion) · \(report.analysisStatus ?? L("legacy report"))"
        }
        if snapshot.backbone?.head != nil { return L("GrantTap Engine Backbone only") }
        return L("No architecture report received")
    }

    private func computerName(_ endpointId: String) -> String {
        ProjectHealthDiagnostics.computerName(
            endpointId, connections: model.connectionRegistry.connections
        )
    }
}
