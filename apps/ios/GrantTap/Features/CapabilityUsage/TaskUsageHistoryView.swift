import SwiftUI

/// This task's own calls: what it reached, what it cost, what failed.
struct TaskUsageHistoryView: View {
    let sessionIds: Set<String>
    @ObservedObject private var usage: CapabilityUsageStore

    init(sessionIds: Set<String>, usage: CapabilityUsageStore? = nil) {
        self.sessionIds = sessionIds
        self.usage = usage ?? .shared
    }

    private var summaries: [OperationalToolSummary] {
        TaskUsageHistory.summaries(usage.events, sessionIds: sessionIds)
    }

    private var calls: [CapabilityUsageEvent] {
        TaskUsageHistory.events(usage.events, sessionIds: sessionIds)
    }

    var body: some View {
        List {
            if let totals = TaskUsageHistory.totals(usage.events, sessionIds: sessionIds) {
                Section(L("This task")) {
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
                }
            }

            // A total says what the task cost; only a shape says when it did.
            let now = Date().timeIntervalSince1970 * 1_000
            let timeline = UsageTimeline.buckets(calls, since: now - 24 * 3_600_000, until: now)
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
                    Text(L("This task has made no observed tool calls."))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(summaries) { summary in
                        // A number that cannot be opened is a dead end: the row
                        // leads to the calls behind it, and each call to the
                        // chat at the moment it happened.
                        NavigationLink {
                            CapabilityUsageHistoryView(
                                kind: summary.kind, name: summary.name,
                                agent: nil, modelName: nil, sessionIds: sessionIds
                            )
                        } label: {
                            UsageToolRow(summary: summary)
                        }
                        .accessibilityIdentifier("task.usage.tool.\(summary.id)")
                    }
                }
            }

            if !calls.isEmpty {
                Section(L("Call history")) {
                    ForEach(calls.prefix(60)) { event in
                        UsageCallLink(event: event)
                    }
                }
            }
        }
        .navigationTitle(L("Task history"))
    }
}
