import Foundation

struct ProviderAccountUsage: Codable, Equatable {
    let provider: String
    let limitId: String
    let observedAt: Double
    let windows: [ProviderUsageWindow]

    var isValid: Bool {
        ["claude", "codex", "cursor", "grok"].contains(provider)
            && !limitId.isEmpty && limitId.utf8.count <= 160
            && observedAt.isFinite && observedAt > 0 && windows.count <= 2
            && Set(windows.map(\.id)).count == windows.count && windows.allSatisfy(\.isValid)
    }
}

struct ProviderUsageWindow: Codable, Equatable, Identifiable {
    let id: String
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Double

    var isValid: Bool {
        ["primary", "secondary"].contains(id) && usedPercent.isFinite
            && (0...100).contains(usedPercent) && windowMinutes > 0
            && resetsAt.isFinite && resetsAt > 0
    }
    var remainingPercent: Int { Int((100 - usedPercent).rounded(.down)) }
}

struct ProviderAccountUsageRow: Identifiable, Equatable {
    let endpointId: String
    let usage: ProviderAccountUsage
    var id: String { "\(endpointId)\u{1f}\(usage.provider)\u{1f}\(usage.limitId)" }

    func isCurrent(at now: Double) -> Bool {
        now - usage.observedAt <= 5 * 60_000 && usage.observedAt - now <= 60_000
    }

    static func resolve(_ catalogs: [ProjectEndpointModelCatalog], provider: String? = nil) -> [Self] {
        var rows: [String: Self] = [:]
        for catalog in catalogs {
            for usage in catalog.accountUsage ?? [] where usage.isValid && (provider == nil || usage.provider == provider) {
                let row = Self(endpointId: catalog.endpointId, usage: usage)
                if rows[row.id].map({ $0.usage.observedAt > usage.observedAt }) != true { rows[row.id] = row }
            }
        }
        return rows.values.sorted { $0.id < $1.id }
    }
}
