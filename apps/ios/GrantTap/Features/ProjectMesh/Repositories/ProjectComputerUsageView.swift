import SwiftUI

/// What one computer has been doing for this Project.
///
/// The Project page answers which machine is carrying the work; this answers
/// what that machine spent doing it — the same shape the task and the Usage
/// tab draw, scoped to the chats this computer ran here.
struct ProjectComputerUsageView: View {
    let endpointId: String
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @ObservedObject private var usage: CapabilityUsageStore

    init(
        endpointId: String, snapshot: ProjectMeshSnapshot, model: AppModel,
        usage: CapabilityUsageStore? = nil
    ) {
        self.endpointId = endpointId
        self.snapshot = snapshot
        self.model = model
        self.usage = usage ?? .shared
    }

    private var events: [CapabilityUsageEvent] {
        ProjectUsageStats.events(
            usage.events, snapshot: snapshot,
            roomByEndpointId: model.projectUsageRooms,
            endpointId: endpointId
        ).sorted { $0.createdAt > $1.createdAt }
    }

    private var summaries: [OperationalToolSummary] {
        UsageSummaries(events: events, totals: []).rows
    }

    private var title: String {
        model.connectionRegistry.connections
            .first { $0.id == endpointId }?.displayName ?? endpointId
    }

    var body: some View {
        let live = ProjectLiveResources.samples(
            snapshot: snapshot, roomByEndpointId: model.projectUsageRooms,
            loadsByRoom: model.machineLoadByRoom,
            nowMs: Date().timeIntervalSince1970 * 1_000
        ).first { $0.endpointId == endpointId }
        let host = ProjectLiveResources.hostSamples(
            snapshot: snapshot, roomByEndpointId: model.projectUsageRooms,
            loadsByRoom: model.machineLoadByRoom,
            nowMs: Date().timeIntervalSince1970 * 1_000
        ).filter { $0.endpointId == endpointId }
        List {
            Section(L("On this computer")) {
                if let totals = ProjectUsageStats.totals(events) {
                    CompatLabeledContent(L("Calls"), value: "\(totals.calls)")
                    if totals.failures > 0 {
                        CompatLabeledContent(L("Failed"), value: "\(totals.failures)")
                    }
                    if let cpu = totals.cpuTimeMs {
                        CompatLabeledContent(L("CPU time"), value: CapabilityResourceFormat.duration(cpu))
                    }
                    if let peak = totals.peakMemoryBytes {
                        CompatLabeledContent(L("Peak memory"), value: CapabilityResourceFormat.bytes(peak))
                    }
                } else {
                    CompatLabeledContent(L("Calls"), value: L("Not reported"))
                    CompatLabeledContent(L("CPU time"), value: L("Not reported"))
                    CompatLabeledContent(L("Peak memory"), value: L("Not reported"))
                }
                CompatLabeledContent(L("Tokens"), value: ProjectUsageStats.reportedTokens(
                    model.sessions + model.allSessionHistory,
                    snapshot: snapshot, endpointId: endpointId
                ).map(Format.tokens) ?? L("Not reported"))
            }
            Section(L("Live execution processes")) {
                if let live {
                    ProjectLiveResourceRow(sample: live, name: title)
                } else {
                    Text(L("No fresh process sample matches an active Mesh execution."))
                        .foregroundStyle(Theme.muted)
                }
            }
            if !host.isEmpty {
                Section(L("Host agent processes")) {
                    ForEach(host) { sample in
                        ProjectHostAgentResourceRow(sample: sample, computerName: title)
                    }
                    Text(L("Shared host load can include other Mesh spaces; it is not attributed to this Mesh."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }

            let now = Date().timeIntervalSince1970 * 1_000
            let timeline = UsageTimeline.buckets(events, since: now - 24 * 3_600_000, until: now)
            if !timeline.isEmpty {
                Section {
                    UsageTimelineChart(buckets: timeline, accent: Theme.accent(for: "claude"))
                } header: {
                    Text(L("Last 24 hours"))
                }
            }

            let shares = UsageBreakdown.shares(summaries)
            if !shares.isEmpty {
                Section {
                    UsageBreakdownChart(shares: shares)
                } header: {
                    Text(L("Where the time went"))
                }
            }

            Section(L("Tools")) {
                if summaries.isEmpty {
                    Text(L("This computer has made no observed tool calls for this Mesh."))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(summaries) { summary in
                        NavigationLink {
                            ProjectUsageEventsView(
                                events: events.filter {
                                    $0.kind == summary.kind && $0.name == summary.name
                                }, title: summary.name
                            )
                        } label: {
                            UsageToolRow(summary: summary)
                        }
                    }
                }
            }

            if !events.isEmpty {
                Section(L("Call history")) {
                    ForEach(events.prefix(60)) { event in
                        UsageCallLink(event: event, model: model)
                    }
                }
            }
        }
        .pageNavigationTitle(title)
    }
}
