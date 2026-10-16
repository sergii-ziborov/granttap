import SwiftUI

struct ProviderAccountUsageRows: View {
    let rows: [ProviderAccountUsageRow]
    var now = Date().timeIntervalSince1970 * 1_000

    var body: some View {
        ForEach(rows) { row in
            VStack(alignment: .leading, spacing: 10) {
                if rows.count > 1 { Text(row.endpointId).font(.caption).foregroundStyle(Theme.muted) }
                ForEach(row.usage.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(DurationFormat.minutes(window.windowMinutes))
                            Spacer()
                            Text(row.isCurrent(at: now) && window.resetsAt > now
                                 ? String(format: L("%d%% remaining"), window.remainingPercent)
                                 : L("Update needed"))
                        }
                        .font(.subheadline.weight(.semibold))
                        if row.isCurrent(at: now) && window.resetsAt > now {
                            ProgressView(value: max(0, 100 - window.usedPercent), total: 100)
                                .tint(window.usedPercent >= 90 ? Theme.riskHigh : Theme.ink)
                        }
                        HStack(spacing: 4) {
                            Text(L("Resets"))
                            Text(Date(timeIntervalSince1970: window.resetsAt / 1_000), style: .relative)
                        }
                        .font(.caption).foregroundStyle(Theme.muted)
                    }
                    .accessibilityIdentifier("usage.limit.\(row.usage.provider).\(window.id)")
                }
                HStack(spacing: 4) {
                    Text(L("Last reported"))
                    Text(Date(timeIntervalSince1970: row.usage.observedAt / 1_000), style: .relative)
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 4)
        }
    }
}

private enum DurationFormat {
    static func minutes(_ value: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = value >= 1_440 ? [.day] : value >= 60 ? [.hour] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(value) * 60) ?? "\(value) min"
    }
}
