import SwiftUI

struct ProjectStatisticsTasksView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    var state: String? = nil

    private var tasks: [ProjectMeshTask] {
        snapshot.tasks.filter { state == nil || $0.state == state }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            if tasks.isEmpty {
                Text(L("No Tasks in this bounded projection."))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(tasks) { task in
                NavigationLink {
                    TaskRouteView(
                        route: .init(projectId: snapshot.projectId, taskId: task.taskId),
                        model: model, onOpenSession: { _ in }, presentedAsSheet: false
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title.isEmpty ? task.goal : task.title).lineLimit(2)
                        Text(ProjectMeshTaskPresentation.label(task.state))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .pageNavigationTitle(L("Tasks"))
    }
}

struct ProjectStatisticsActivityView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section(L("Executions")) {
                ForEach(snapshot.executions) { execution in
                    NavigationLink {
                        TaskRouteView(
                            route: .init(projectId: snapshot.projectId, taskId: execution.taskId),
                            model: model, onOpenSession: { _ in }, presentedAsSheet: false
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(MeshActorPresentation.executionName(execution))
                            Text(execution.computerId)
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            Section(L("Mesh events")) {
                if snapshot.events.isEmpty {
                    Text(L("No events in this bounded projection."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(snapshot.events.sorted { $0.createdAt > $1.createdAt }) { event in
                    NavigationLink {
                        TaskRouteView(
                            route: .init(projectId: snapshot.projectId, taskId: event.taskId),
                            model: model, onOpenSession: { _ in }, presentedAsSheet: false
                        )
                    } label: {
                        ProjectMeshTimelineRow(event: event)
                    }
                }
            }
        }
        .pageNavigationTitle(L("Activity"))
    }
}

struct ProjectStatisticsUsageView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @ObservedObject private var usage: CapabilityUsageStore

    init(snapshot: ProjectMeshSnapshot, model: AppModel, usage: CapabilityUsageStore? = nil) {
        self.snapshot = snapshot
        self.model = model
        self.usage = usage ?? .shared
    }

    private var scopedEvents: [CapabilityUsageEvent] {
        ProjectUsageStats.events(usage.events, snapshot: snapshot,
                                 roomByEndpointId: model.projectUsageRooms)
    }
    private var totals: (calls: Int, failures: Int, peakMemoryBytes: Int?, cpuTimeMs: Int?)? {
        ProjectUsageStats.totals(scopedEvents)
    }

    var body: some View {
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
            Section(L("Measured usage")) {
                CompatLabeledContent(L("Tokens"), value: ProjectUsageStats.reportedTokens(
                    model.sessions + model.allSessionHistory, snapshot: snapshot
                ).map(Format.tokens) ?? L("Not reported"))
                CompatLabeledContent(L("Tool calls"), value: totals.map { "\($0.calls)" }
                    ?? L("Not reported"))
                CompatLabeledContent(L("CPU time"), value: totals?.cpuTimeMs.map {
                    CapabilityResourceFormat.duration($0)
                } ?? L("Not reported"))
                CompatLabeledContent(L("Peak memory"), value: totals?.peakMemoryBytes.map {
                    CapabilityResourceFormat.bytes($0)
                } ?? L("Not reported"))
            }
            Section(L("By computer")) {
                let computers = ProjectUsageStats.perComputer(
                    scopedEvents, snapshot: snapshot,
                    roomByEndpointId: model.projectUsageRooms
                )
                if computers.isEmpty {
                    Text(L("No resource samples were attributed to this Mesh."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(computers) { computer in
                    NavigationLink {
                        ProjectComputerUsageView(
                            endpointId: computer.endpointId, snapshot: snapshot, model: model
                        )
                    } label: {
                        ProjectComputerUsageRow(usage: computer, model: model)
                    }
                }
            }
            Section(L("Live execution processes")) {
                if live.isEmpty {
                    Text(L("No fresh process sample matches an active Mesh execution."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(live) { sample in
                    NavigationLink {
                        ProjectComputerUsageView(
                            endpointId: sample.endpointId, snapshot: snapshot, model: model
                        )
                    } label: {
                        ProjectLiveResourceRow(
                            sample: sample,
                            name: ProjectHealthDiagnostics.computerName(
                                sample.endpointId, connections: model.connectionRegistry.connections
                            )
                        )
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
                                sample: sample,
                                computerName: ProjectHealthDiagnostics.computerName(
                                    sample.endpointId, connections: model.connectionRegistry.connections
                                )
                            )
                        }
                    }
                    Text(L("Shared host load can include other Mesh spaces; it is not attributed to this Mesh."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Section(L("By Task")) {
                ForEach(snapshot.tasks) { task in
                    let taskEvents = ProjectUsageStats.events(
                        scopedEvents, snapshot: snapshot,
                        roomByEndpointId: model.projectUsageRooms,
                        taskId: task.taskId
                    )
                    NavigationLink {
                        ProjectUsageEventsView(events: taskEvents, title: L("Task history"))
                    } label: {
                        Text(task.title.isEmpty ? task.goal : task.title).lineLimit(2)
                    }
                }
            }
        }
        .pageNavigationTitle(L("Usage"))
    }
}
