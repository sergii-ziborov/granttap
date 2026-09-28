import Foundation

/// What one task spent, separately from every other task.
///
/// Usage answers "what has this computer been doing"; standing inside a task,
/// the question is narrower and the global numbers cannot answer it — a tool
/// used heavily elsewhere says nothing about the task being read.
enum TaskUsageHistory {
    /// The calls this task made, newest first.
    ///
    /// A task keeps its identity across provider and computer changes while its
    /// session id does not, so both the resolved id and the one the events were
    /// recorded under are accepted.
    static func events(
        _ all: [CapabilityUsageEvent], sessionIds: Set<String>
    ) -> [CapabilityUsageEvent] {
        all.filter { event in
            guard let sessionId = event.sessionId else { return false }
            return sessionIds.contains(sessionId)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Per-tool rows for this task, heaviest first, from its own calls only.
    static func summaries(
        _ all: [CapabilityUsageEvent], sessionIds: Set<String>
    ) -> [OperationalToolSummary] {
        UsageSummaries(events: events(all, sessionIds: sessionIds), totals: []).rows
    }

    /// What the task cost in total, when anything was observed at all.
    static func totals(
        _ all: [CapabilityUsageEvent], sessionIds: Set<String>
    ) -> (calls: Int, failures: Int, peakMemoryBytes: Int?, cpuTimeMs: Int?)? {
        let rows = events(all, sessionIds: sessionIds)
        guard !rows.isEmpty else { return nil }
        let peak = rows.compactMap { $0.resource?.effectivePeakRssBytes }.max()
        let cpu = rows.compactMap { $0.resource?.effectiveCpuTimeMs }
        return (
            calls: rows.count,
            failures: rows.filter { $0.effectiveOutcome == .error }.count,
            peakMemoryBytes: peak,
            // A sum, because CPU time is spent per call and adds up across them.
            cpuTimeMs: cpu.isEmpty ? nil : cpu.reduce(0, +)
        )
    }
}
