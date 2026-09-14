import SwiftUI

struct CapabilityUsageView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var usage = CapabilityUsageStore.shared
    @ObservedObject private var totals = CapabilityTotalsStore.shared
    @ObservedObject private var audit = AuditStore.shared
    @State private var period: UsagePeriod = .seven
    @State private var kind: UsageKindFilter = .all
    @State private var provider = "all"
    @State private var showClearConfirmation = false

    private var cutoff: Double {
        Date().timeIntervalSince1970 * 1000 - Double(period.rawValue) * 3_600_000
    }

    private var periodEvents: [CapabilityUsageEvent] {
        sourceEvents.filter { event in
            event.createdAt >= cutoff
                && kind.includes(event)
                && (provider == "all" || AgentIdentity.normalize(event.agent ?? "") == provider)
        }
    }

    private var periodSessions: [SessionInfo] {
        (model.sessions + model.allSessionHistory).filter { $0.lastActivityAt >= cutoff }
    }

    /// Totals for the selected period, when a computer published that window.
    private var periodTotals: [CapabilityUsageTotal] {
        guard provider == "all", let days = period.publishedDays,
              let window = totals.window(forDays: days) else { return [] }
        return totals.named(windowHours: window)
            .compactMap(kind.selectedTotal)
    }

    private var usageSummaries: UsageSummaries {
        UsageSummaries(events: periodEvents, totals: periodTotals)
    }

    private var summaries: [OperationalToolSummary] { usageSummaries.rows }

    private var providers: [String] {
        Array(Set(sourceEvents.compactMap(\.agent).map(AgentIdentity.normalize))).sorted()
    }

    private var sourceEvents: [CapabilityUsageEvent] {
        model.demoMode ? usage.events + UsageDemoFixtures.events() : usage.events
    }

    /// The most calls of one tool in flight at once, by tool row id.
    var parallelByTool: [String: Int] { UsageConcurrency.maxParallelByName(periodEvents) }

    /// Distinct skills run in the period, whichever filter is up.
    private var skillsUsed: Set<String> {
        Set(sourceEvents.filter { $0.kind == .skill && $0.createdAt >= cutoff }.map(\.name))
    }

    /// Those same skills as rows, so the figure opens into the calls it counted.
    private var skillSummaries: [OperationalToolSummary] {
        UsageSummaries(
            events: sourceEvents.filter { $0.kind == .skill && $0.createdAt >= cutoff },
            totals: []
        ).rows
    }

    var body: some View {
        List {
            Section {
                Picker(L("Period"), selection: $period) {
                    ForEach(UsagePeriod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            // Every figure opens what it counted: a number nobody can look
            // into is a claim a person has to take on trust.
            Section(L("Overview")) {
                metricLink("Sessions", periodSessions.count) {
                    UsageChatsView(title: L("Sessions"), sessions: periodSessions)
                }
                metricLink("Tokens", periodSessions.reduce(0) { $0 + $1.tokensSession }, formatted: true) {
                    UsageChatsView(title: L("Tokens"), sessions: periodSessions, order: .tokens)
                }
                // Skills were invisible unless the filter was flipped to them.
                metricLink("Skills used", skillsUsed.count) {
                    UsageToolListView(title: L("Skills used"), summaries: skillSummaries,
                                      agent: provider == "all" ? nil : provider)
                }
                metricLink("Waiting for you", model.pending.count + model.questions.count
                           + model.meshNeedsYouEvents.count) {
                    UsageWaitingView()
                }
                metricLink("Approvals", model.demoMode ? 6 : audit.events.filter {
                    $0.createdAt >= cutoff && $0.action == "decision"
                }.count) {
                    AuditLogView(audit: audit)
                }
                metricLink("Tool calls", usageSummaries.toolCalls) {
                    UsageToolListView(title: L("Tool calls"), summaries: summaries,
                                      agent: provider == "all" ? nil : provider)
                }
                metricLink("Active computers", model.demoMode ? 2 : model.connectionRegistry.connections.filter {
                    model.snapshotForConnection($0).phase == .live
                }.count) {
                    UsageComputersView()
                }
            }

            Section {
                Picker(L("Tools"), selection: $kind) {
                    ForEach(UsageKindFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if providers.count > 1 {
                    Picker(L("Provider"), selection: $provider) {
                        Text(L("All providers")).tag("all")
                        ForEach(providers, id: \.self) { id in
                            Text(AgentIdentity.displayName(id)).tag(id)
                        }
                    }
                }
            }

            // When the period was busy, before what it was busy with.
            let now = Date().timeIntervalSince1970 * 1_000
            let timeline = UsageTimeline.buckets(
                periodEvents, since: now - 24 * 3_600_000, until: now
            )
            if !timeline.isEmpty {
                Section {
                    UsageTimelineChart(buckets: timeline, accent: Theme.accent(for: "claude"))
                } header: {
                    Text(L("Last 24 hours"))
                }
            }

            // When calls overlapped: the shape of a machine getting warm.
            let parallel = UsageConcurrency.buckets(periodEvents, since: now - 24 * 3_600_000, until: now)
            if parallel.contains(where: { $0.calls > 1 }) {
                Section {
                    UsageTimelineChart(buckets: parallel, accent: Theme.accent(for: "codex"))
                } header: {
                    Text(L("In flight at once, last 24 hours"))
                } footer: {
                    Text(L("The tallest bar is the moment the most calls overlapped."))
                }
            }

            // Where the period actually went, before the list of names.
            if !UsageBreakdown.shares(summaries).isEmpty {
                Section {
                    UsageBreakdownChart(shares: UsageBreakdown.shares(summaries))
                } header: {
                    Text(L("Where the time went"))
                } footer: {
                    Text(L("Bars are time spent, not calls made: many quick calls are not what slowed a session down."))
                }
            }

            Section(L("Tools")) {
                if summaries.isEmpty {
                    Text(L("No observed tool calls in this period."))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(summaries) { summary in
                        // Every row opens the observations behind its number.
                        // The detail view existed but nothing reached it, so a
                        // count of failures was a dead end.
                        NavigationLink {
                            CapabilityUsageHistoryView(
                                kind: summary.kind, name: summary.name,
                                agent: provider == "all" ? nil : provider, modelName: nil,
                                outcome: kind == .failed ? .error : nil
                            )
                        } label: {
                            toolRow(summary)
                        }
                        .accessibilityIdentifier("usage.tool.\(summary.id)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(L("Clear local usage history"), role: .destructive) {
                        showClearConfirmation = true
                    }
                    .disabled(usage.events.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog(L("Clear usage history?"), isPresented: $showClearConfirmation) {
            Button(L("Clear history"), role: .destructive) { usage.clear() }
            Button(L("Cancel"), role: .cancel) {}
        }
    }
}
