import Foundation

/// How many calls were in flight at once.
///
/// A count of calls says how much happened; it cannot say whether three
/// searches ran one after another or all together, and the machine only
/// warms up in the second case. Each call is the interval from when it
/// started to when its result came back; the most intervals open at any
/// moment is the answer.
enum UsageConcurrency {
    struct Interval: Equatable {
        let start: Double
        let end: Double
    }

    /// A call without a measured duration is an instant: it still overlaps
    /// itself, so a burst of instants at one moment still counts as a burst.
    static func intervals(_ events: [CapabilityUsageEvent]) -> [Interval] {
        events.map { event in
            let end = event.createdAt
            return Interval(start: end - Double(max(0, event.durationMs ?? 0)), end: end)
        }
    }

    /// The most calls open at one moment.
    static func maxParallel(_ events: [CapabilityUsageEvent]) -> Int {
        maxOpen(intervals(events))
    }

    static func maxParallelByKind(_ events: [CapabilityUsageEvent]) -> [CapabilityUsageKind: Int] {
        Dictionary(grouping: events, by: \.kind).mapValues(maxParallel)
    }

    static func maxParallelByName(_ events: [CapabilityUsageEvent]) -> [String: Int] {
        Dictionary(grouping: events) { "\($0.kind.rawValue):\($0.name)" }.mapValues(maxParallel)
    }

    /// Per slice of the window, the most calls open inside it, shaped like the
    /// call timeline so the same chart draws both.
    static func buckets(
        _ events: [CapabilityUsageEvent], since: Double, until: Double, slices: Int = 24
    ) -> [UsageTimelineBucket] {
        guard slices > 0, until > since else { return [] }
        let width = (until - since) / Double(slices)
        let all = intervals(events)
        var peaks = Array(repeating: 0, count: slices)
        for slice in 0..<slices {
            let from = since + Double(slice) * width
            let to = from + width
            let overlapping = all.filter { $0.end >= from && $0.start <= to }
            peaks[slice] = maxOpen(overlapping.map {
                Interval(start: max($0.start, from), end: min($0.end, to))
            })
        }
        guard let peak = peaks.max(), peak > 0 else { return [] }
        return (0..<slices).map { slice in
            UsageTimelineBucket(
                startedAt: since + Double(slice) * width, calls: peaks[slice], failures: 0,
                fraction: Double(peaks[slice]) / Double(peak)
            )
        }
    }

    private static func maxOpen(_ intervals: [Interval]) -> Int {
        var marks: [(at: Double, delta: Int)] = []
        for interval in intervals {
            marks.append((interval.start, 1))
            marks.append((interval.end, -1))
        }
        // At one instant, starts come before ends: a call that ends exactly
        // when another starts overlapped it for that instant, and an instant
        // call overlaps itself.
        marks.sort { $0.at == $1.at ? $0.delta > $1.delta : $0.at < $1.at }
        var open = 0
        var peak = 0
        for mark in marks {
            open += mark.delta
            peak = max(peak, open)
        }
        return peak
    }
}

/// One kind of capability — MCP, skills, CLI — over the period, as one row.
struct UsageKindTotal: Identifiable, Equatable {
    let kind: CapabilityUsageKind
    let calls: Int
    let failures: Int
    let totalDurationMs: Int
    let cpuTimeMs: Int
    let peakMemoryBytes: Int?
    let maxParallel: Int
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .mcp: return "MCP"
        case .skill: return L("Skills")
        case .cli: return "CLI"
        }
    }
}

enum UsageKindTotals {
    static func rows(_ events: [CapabilityUsageEvent]) -> [UsageKindTotal] {
        let parallel = UsageConcurrency.maxParallelByKind(events)
        return CapabilityUsageKind.allCases.compactMap { kind in
            let mine = events.filter { $0.kind == kind }
            guard !mine.isEmpty else { return nil }
            return UsageKindTotal(
                kind: kind,
                calls: mine.count,
                failures: mine.filter { $0.effectiveOutcome == .error }.count,
                totalDurationMs: mine.reduce(0) { $0 + ($1.durationMs ?? 0) },
                cpuTimeMs: mine.reduce(0) { $0 + ($1.resource?.cpuTimeMs ?? 0) },
                peakMemoryBytes: mine.compactMap { $0.resource?.effectivePeakRssBytes }.max(),
                maxParallel: parallel[kind] ?? 0
            )
        }
    }
}
