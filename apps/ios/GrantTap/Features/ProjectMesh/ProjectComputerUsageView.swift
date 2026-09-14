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

    /// The chats this computer ran for the Project, under every id they wore.
    var sessionIds: Set<String> {
        Set(ProjectUsageStats.computerBySession(snapshot)
            .filter { $0.value == endpointId }.keys)
    }

    private var events: [CapabilityUsageEvent] {
        TaskUsageHistory.events(usage.events, sessionIds: sessionIds)
    }

    private var summaries: [OperationalToolSummary] {
        TaskUsageHistory.summaries(usage.events, sessionIds: sessionIds)
    }

    private var title: String {
        model.connectionRegistry.connections
            .first { $0.id == endpointId }?.displayName ?? endpointId
    }

    var body: some View {
        List {
            if let totals = TaskUsageHistory.totals(usage.events, sessionIds: sessionIds) {
                Section(L("On this computer")) {
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
                    CompatLabeledContent(
                        L("Tokens"), value: Format.tokens(ProjectUsageStats.tokens(
                            model.sessions + model.allSessionHistory, sessionIds: sessionIds
                        ))
                    )
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
                    Text(L("This computer has made no observed tool calls for this Project."))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(summaries) { summary in
                        NavigationLink {
                            CapabilityUsageHistoryView(
                                kind: summary.kind, name: summary.name,
                                agent: nil, modelName: nil, sessionIds: sessionIds
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
        .navigationTitle(title)
    }
}
