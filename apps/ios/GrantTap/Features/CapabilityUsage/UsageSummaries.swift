import Foundation

struct OperationalToolSummary: Identifiable, Equatable {
    let kind: CapabilityUsageKind
    let name: String
    let count: Int
    let failures: Int
    let cancelled: Int
    let averageDurationMs: Int?
    let lastUsedAt: Double
    var peakMemoryBytes: Int? = nil
    var cpuTimeMs: Int? = nil
    var id: String { "\(kind.rawValue):\(name)" }

    var resourceDetail: String? {
        let values = [
            peakMemoryBytes.map { "\(CapabilityResourceFormat.bytes($0)) peak" },
            cpuTimeMs.map { "\($0) ms CPU" },
        ].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

enum CapabilityResourceFormat {
    /// CPU time is spent, not sampled, so it reads as a duration.
    static func duration(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "—" }
        if milliseconds < 1_000 { return String(format: L("%dms"), milliseconds) }
        if milliseconds < 60_000 {
            return String(format: L("%.1fs"), Double(milliseconds) / 1_000)
        }
        return String(format: L("%dm %ds"), milliseconds / 60_000, (milliseconds % 60_000) / 1_000)
    }

    static func bytes(_ value: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(max(0, value))
        var unit = 0
        while amount >= 1_024, unit < units.count - 1 {
            amount /= 1_024
            unit += 1
        }
        return String(format: amount >= 10 || unit == 0 ? "%.0f %@" : "%.1f %@",
                      amount, units[unit])
    }
}

/// One row per capability for the selected period.
///
/// Counts come from the computer whenever it published totals for the period:
/// the observation feed is trimmed to a byte budget, so counting the events the
/// phone holds answers for hours rather than the days the picker offers. The
/// events still supply durations, which totals do not carry.
struct UsageSummaries {
    let events: [CapabilityUsageEvent]
    let totals: [CapabilityUsageTotal]

    /// Failures first, then the busiest; equal rows keep one order by name,
    /// so a list that is redrawn on every report does not shuffle its ties.
    var rows: [OperationalToolSummary] {
        (totals.isEmpty ? observed : published).sorted(by: Self.heaviestFirst)
    }

    static func heaviestFirst(_ lhs: OperationalToolSummary, _ rhs: OperationalToolSummary) -> Bool {
        if lhs.failures != rhs.failures { return lhs.failures > rhs.failures }
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// Calls in the period, from totals when the computer counted them.
    var toolCalls: Int {
        totals.isEmpty ? events.count : totals.reduce(0) { $0 + $1.count }
    }

    private var durationsByRow: [String: [Int]] {
        Dictionary(grouping: events) { "\($0.kind.rawValue):\($0.name)" }
            .mapValues { $0.compactMap(\.durationMs) }
    }

    private var published: [OperationalToolSummary] {
        let durations = durationsByRow
        return totals.compactMap { row in
            guard let name = row.name else { return nil }
            return OperationalToolSummary(
                kind: row.kind, name: name, count: row.count,
                failures: row.failures, cancelled: row.cancelled,
                averageDurationMs: Self.average(durations["\(row.kind.rawValue):\(name)"] ?? []),
                lastUsedAt: row.lastUsedAt,
                peakMemoryBytes: Self.peakMemory(events, kind: row.kind, name: name),
                cpuTimeMs: Self.cpuTime(events, kind: row.kind, name: name)
            )
        }
    }

    private var observed: [OperationalToolSummary] {
        Dictionary(grouping: events) { "\($0.kind.rawValue):\($0.name)" }
            .compactMap { _, events in
                guard let first = events.first else { return nil }
                return OperationalToolSummary(
                    kind: first.kind, name: first.name, count: events.count,
                    failures: events.filter { $0.effectiveOutcome == .error }.count,
                    cancelled: events.filter { $0.effectiveOutcome == .cancelled }.count,
                    averageDurationMs: Self.average(events.compactMap(\.durationMs)),
                    lastUsedAt: events.map(\.createdAt).max() ?? 0,
                    peakMemoryBytes: events.compactMap {
                        $0.resource?.effectivePeakRssBytes
                    }.max(),
                    cpuTimeMs: Self.sum(events.compactMap {
                        $0.resource?.effectiveCpuTimeMs
                    })
                )
            }
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private static func peakMemory(_ events: [CapabilityUsageEvent],
                                   kind: CapabilityUsageKind, name: String) -> Int? {
        events.filter { $0.kind == kind && $0.name == name }
            .compactMap { $0.resource?.effectivePeakRssBytes }.max()
    }

    private static func cpuTime(_ events: [CapabilityUsageEvent],
                                kind: CapabilityUsageKind, name: String) -> Int? {
        sum(events.filter { $0.kind == kind && $0.name == name }
            .compactMap { $0.resource?.effectiveCpuTimeMs })
    }

    private static func sum(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0) { total, value in
            let result = total.addingReportingOverflow(value)
            return result.overflow ? Int.max : result.partialValue
        }
    }
}
