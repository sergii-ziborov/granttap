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

    /// Totals for the selected period, when a computer published that window.
    private var overviewTotals: [CapabilityUsageTotal] {
        guard let days = period.publishedDays,
              let window = totals.window(forDays: days) else { return [] }
        return totals.summaries(windowHours: window)
    }

    private var sourceEvents: [CapabilityUsageEvent] {
        model.demoMode ? usage.events + UsageDemoFixtures.events() : usage.events
    }

    /// Retained for callers outside body; rendered rows receive the shared map.
    var parallelByTool: [String: Int] {
        let since = cutoff
        let events = sourceEvents.filter {
            $0.createdAt >= since && kind.includes($0)
                && (provider == "all" || AgentIdentity.normalize($0.agent ?? "") == provider)
        }
        return UsageConcurrency.maxParallelByName(events)
    }

    var body: some View {
        let now = Date().timeIntervalSince1970 * 1_000
        let since = now - Double(period.rawValue) * 3_600_000
        let events = sourceEvents
        let periodSummary = UsagePeriodSummary(events: events, totals: overviewTotals, since: since, until: now)
        let overview = periodSummary.overview
        let tools = periodSummary.tools(kind: kind, provider: provider)
        let summaries = tools.rows
        let skillSummaries = overview.rows.filter { $0.kind == .skill }
        let periodSessions = (model.sessions + model.allSessionHistory).filter { $0.lastActivityAt >= since }
        let providers = Array(Set(events.compactMap(\.agent).map(AgentIdentity.normalize))).sorted()
        let parallelByTool = UsageConcurrency.maxParallelByName(tools.events)
        let timeline = UsageTimeline.buckets(tools.events, since: now - 24 * 3_600_000, until: now)
        let parallel = UsageConcurrency.buckets(tools.events, since: now - 24 * 3_600_000, until: now)
        let shares = UsageBreakdown.shares(summaries)
        List {
            #if targetEnvironment(macCatalyst)
            if let error = model.localMCPReader?.usageError {
                Section { Text(error).foregroundStyle(Theme.riskMed) }
            }
            #endif
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
                metricLink("Skills used", Set(skillSummaries.map(\.name)).count) {
                    UsageToolListView(title: L("Skills used"), summaries: skillSummaries,
                                      since: since, until: periodSummary.until)
                }
                metricLink("Waiting for you", model.pending.count + model.questions.count
                           + model.meshNeedsYouEvents.count) {
                    UsageWaitingView()
                }
                metricLink("Approvals", model.demoMode ? 6 : audit.events.filter {
                    $0.createdAt >= since && $0.action == "decision"
                }.count) {
                    AuditLogView(audit: audit)
                }
                metricLink("Tool calls", overview.toolCalls) {
                    UsageToolListView(title: L("Tool calls"), summaries: overview.rows,
                                      since: since, until: periodSummary.until)
                }
                metricLink("Active computers", activeComputerCount) {
                    UsageComputersView()
                }
            }

            ProviderUsageSection(model: model, sessions: periodSessions)

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
            if !timeline.isEmpty {
                Section {
                    UsageTimelineChart(buckets: timeline, accent: Theme.accent(for: "claude"))
                } header: {
                    Text(L("Last 24 hours"))
                }
            }

            // When calls overlapped: the shape of a machine getting warm.
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
            if !shares.isEmpty {
                Section {
                    UsageBreakdownChart(shares: shares)
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
                                outcome: kind == .failed ? .error : nil,
                                since: since, until: periodSummary.until, summary: summary
                            )
                        } label: {
                            toolRow(summary, maxParallel: parallelByTool[summary.id] ?? 0)
                        }
                        .accessibilityIdentifier("usage.tool.\(summary.id)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.refreshProviderMetadata() }
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

    private var activeComputerCount: Int {
        if model.demoMode { return 2 }
        let connected = model.connectionRegistry.connections.filter {
            model.snapshotForConnection($0).phase == .live
        }.count
        #if targetEnvironment(macCatalyst)
        return connected + (model.localMCPReader?.status != nil ? 1 : 0)
        #else
        return connected
        #endif
    }
}
