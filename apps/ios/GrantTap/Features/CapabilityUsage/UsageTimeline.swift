import Foundation

/// One slice of a period, with what happened inside it.
struct UsageTimelineBucket: Identifiable, Equatable {
    let startedAt: Double
    let calls: Int
    let failures: Int
    /// 0…1 of the busiest slice, so the tallest bar is always full.
    let fraction: Double

    var id: Double { startedAt }
}

/// Calls over time, rather than calls in total.
///
/// A period total says what something cost; it cannot say when. "It got slow
/// around four" and "it has been slow all week" produce the same total and want
/// very different answers, and only a shape over time tells them apart.
enum UsageTimeline {
    /// Bucket calls into a fixed number of slices across the window.
    ///
    /// The slice count is fixed rather than the slice width, so an hour and a
    /// month draw the same chart and the axis never has to be explained.
    static func buckets(
        _ events: [CapabilityUsageEvent],
        since: Double,
        until: Double,
        slices: Int = 24
    ) -> [UsageTimelineBucket] {
        guard slices > 0, until > since else { return [] }
        let width = (until - since) / Double(slices)
        var calls = Array(repeating: 0, count: slices)
        var failures = Array(repeating: 0, count: slices)
        for event in events where event.createdAt >= since && event.createdAt <= until {
            let offset = Int((event.createdAt - since) / width)
            let index = min(max(offset, 0), slices - 1)
            calls[index] += 1
            if event.effectiveOutcome == .error { failures[index] += 1 }
        }
        guard let peak = calls.max(), peak > 0 else { return [] }
        return (0..<slices).map { index in
            UsageTimelineBucket(
                startedAt: since + Double(index) * width,
                calls: calls[index],
                failures: failures[index],
                fraction: Double(calls[index]) / Double(peak)
            )
        }
    }
}
