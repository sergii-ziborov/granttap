import SwiftUI

/// One line of the Usage screen at a time: a figure, a tool, a kind of
/// capability, and the words each is read in.
extension CapabilityUsageView {
    func metric(_ title: String, _ value: Int, formatted: Bool = false) -> some View {
        HStack {
            Text(L(title))
            Spacer()
            Text(formatted ? Format.tokens(value) : "\(value)")
                .font(Theme.mono(14, .semibold))
        }
    }

    /// A figure that opens what it counted.
    func metricLink<Destination: View>(
        _ title: String, _ value: Int, formatted: Bool = false,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink { destination() } label: { metric(title, value, formatted: formatted) }
            .accessibilityIdentifier("usage.open-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    func toolRow(_ summary: OperationalToolSummary, maxParallel: Int? = nil) -> some View {
        CapabilityUsageToolRow(summary: summary, maxParallel: maxParallel)
    }
}

/// Keep formatting in a row's body so List only builds it when needed.
@MainActor
private struct CapabilityUsageToolRow: View {
    let summary: OperationalToolSummary
    let maxParallel: Int?
    private static let relativeDate = RelativeDateTimeFormatter()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon(summary.kind)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                // One line that wraps, not three boxes that elbow each other
                // into an ellipsis.
                Text(detail)
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(summary.count)×").font(Theme.mono(13, .bold))
                if summary.failures > 0 {
                    Text(String(format: L("%d failed"), summary.failures))
                        .font(.caption2).foregroundStyle(Theme.riskHigh)
                } else if summary.cancelled > 0 {
                    Text(String(format: L("%d cancelled"), summary.cancelled))
                        .font(.caption2).foregroundStyle(Theme.muted)
                } else {
                    Text(L("Success")).font(.caption2).foregroundStyle(Theme.ok)
                }
            }
        }
    }

    private var detail: String {
        let ago = Self.relativeDate.localizedString(
            for: Date(timeIntervalSince1970: summary.lastUsedAt / 1000), relativeTo: Date()
        )
        let atOnce = maxParallel.flatMap { $0 > 1 ? String(format: L("%d at once"), $0) : nil }
        return [
            summary.averageDurationMs.map { String(format: L("avg %@"), Format.latencyMs($0)) },
            summary.resourceDetail,
            atOnce,
            ago,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    func icon(_ kind: CapabilityUsageKind) -> String {
        switch kind {
        case .mcp: return "shippingbox"
        case .skill: return "wand.and.stars"
        case .cli: return "terminal"
        }
    }
}
