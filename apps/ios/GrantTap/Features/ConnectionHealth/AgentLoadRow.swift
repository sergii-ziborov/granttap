import SwiftUI

/// Formatting for measured load. Kept pure so the numbers the phone shows can
/// be asserted directly, without building a view.
enum ConnectionLoadFormat {
    static func age(seconds: Int?) -> String {
        guard let seconds else { return L("never") }
        if seconds < 60 { return String(format: L("%ds ago"), seconds) }
        if seconds < 3_600 { return String(format: L("%dm ago"), seconds / 60) }
        if seconds < 86_400 { return String(format: L("%dh ago"), seconds / 3_600) }
        return String(format: L("%dd ago"), seconds / 86_400)
    }

    static func bytes(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB"]
        var amount = value
        var unit = 0
        while amount >= 1_024, unit < units.count - 1 {
            amount /= 1_024
            unit += 1
        }
        return String(format: amount >= 10 || unit == 0 ? "%.0f %@" : "%.1f %@",
                      amount, units[unit])
    }

    static func cpu(_ percent: Double) -> String {
        percent <= 0 ? "—" : String(format: "%.1f%%", percent)
    }

    static func cpuAndMemory(cpuPercent: Double, memoryBytes: Double) -> String {
        "\(cpu(cpuPercent)) · \(bytes(memoryBytes))"
    }

    static func duration(ms: Double) -> String {
        guard ms > 0 else { return "—" }
        return ms < 1_000
            ? String(format: L("%dms"), Int(ms))
            : String(format: L("%.1fs"), ms / 1_000)
    }

    static func tokens(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fk", value / 1_000) }
        return String(format: "%.0f", value)
    }

    static func share(_ fraction: Double?) -> String? {
        guard let fraction, fraction > 0 else { return nil }
        return String(format: "%.0f%%", fraction * 100)
    }
}

struct AgentLoadRow: View {
    let sample: AgentLoadSample
    let share: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentGlyph(agent: sample.agent, size: 22)
                Text(sample.agent.capitalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let share = ConnectionLoadFormat.share(share) {
                    Text(String(format: L("%@ of load"), share))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel(String(format: L("%@ of measured agent CPU"), share))
                }
            }

            if let fraction = share, fraction > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule()
                            .fill(Theme.accent(for: sample.agent))
                            .frame(width: max(2, geometry.size.width * fraction))
                    }
                }
                .frame(height: 5)
            }

            HStack(spacing: 14) {
                metric(L("CPU"), ConnectionLoadFormat.cpu(sample.cpuPercent))
                metric(L("Memory"), ConnectionLoadFormat.bytes(sample.memoryBytes))
                metric(L("Scan"), ConnectionLoadFormat.duration(ms: sample.scanMs))
                metric(L("Tokens"), ConnectionLoadFormat.tokens(sample.tokensRecent))
            }

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let processes = sample.processes == 0
            ? L("no running process")
            : LPlural(sample.processes, one: "%d process", many: "%d processes")
        let chats = LPlural(sample.sessions, one: "%d chat", many: "%d chats")
        return "\(processes) · \(chats)"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(Theme.mono(13, .semibold))
                .foregroundStyle(Theme.ink)
        }
    }
}
