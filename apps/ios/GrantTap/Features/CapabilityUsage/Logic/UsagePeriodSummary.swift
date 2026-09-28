import Foundation

/// The overview covers a period; the controls below it filter only its tool list.
struct UsagePeriodSummary {
    let events: [CapabilityUsageEvent]
    let totals: [CapabilityUsageTotal]
    let since: Double
    let until: Double

    init(events: [CapabilityUsageEvent], totals: [CapabilityUsageTotal],
         since: Double, until: Double) {
        self.events = events.filter { $0.createdAt >= since && $0.createdAt <= until }
        self.totals = totals
        self.since = since
        self.until = until
    }

    var overview: UsageSummaries { UsageSummaries(events: events, totals: totals) }
    var skills: [OperationalToolSummary] { overview.rows.filter { $0.kind == .skill } }

    func tools(kind: UsageKindFilter, provider: String) -> UsageSummaries {
        UsageSummaries(events: events.filter {
            kind.includes($0)
                && (provider == "all" || AgentIdentity.normalize($0.agent ?? "") == provider)
        }, totals: provider == "all" ? totals.compactMap(kind.selectedTotal) : [])
    }
}
