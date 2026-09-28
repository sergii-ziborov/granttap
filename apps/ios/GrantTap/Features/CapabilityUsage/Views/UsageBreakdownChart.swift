import SwiftUI

/// One tool's share of the period, as a bar.
struct UsageShare: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: CapabilityUsageKind
    let calls: Int
    let failures: Int
    /// 0…1 of the period's busiest tool, so the widest bar is always full.
    let fraction: Double
}

enum UsageBreakdown {
    /// The tools worth drawing, heaviest first.
    ///
    /// Time spent is the axis, not call count: a hundred instant calls are not
    /// what made a session slow, and one long call that did would otherwise
    /// disappear behind them. Tools with no measured duration fall back to
    /// their share of calls rather than vanishing.
    static func shares(_ rows: [OperationalToolSummary], limit: Int = 6) -> [UsageShare] {
        let weighted = rows.map { row -> (OperationalToolSummary, Double) in
            let duration = row.averageDurationMs.map { Double($0) * Double(row.count) }
            return (row, duration ?? Double(row.count))
        }
        guard let peak = weighted.map(\.1).max(), peak > 0 else { return [] }
        return weighted
            .sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }
            .prefix(limit)
            .map { row, weight in
                UsageShare(
                    id: row.id, name: row.name, kind: row.kind,
                    calls: row.count, failures: row.failures,
                    fraction: min(1, max(0.02, weight / peak))
                )
            }
    }
}

struct UsageBreakdownChart: View {
    let shares: [UsageShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(shares) { share in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(share.name).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(String(format: L("%d×"), share.calls))
                            .font(.caption).foregroundStyle(Theme.muted)
                        if share.failures > 0 {
                            Text(String(format: L("%d failed"), share.failures))
                                .font(.caption).foregroundStyle(Theme.riskHigh)
                        }
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.muted.opacity(0.15))
                            Capsule()
                                .fill(colour(share.kind))
                                .frame(width: max(3, geometry.size.width * share.fraction))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func colour(_ kind: CapabilityUsageKind) -> Color {
        switch kind {
        case .mcp: return Theme.accent(for: "claude")
        case .skill: return Theme.ok
        case .cli: return Theme.riskMed
        }
    }
}
