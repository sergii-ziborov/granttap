import Foundation
import SwiftUI

/// Authenticated computer summaries remain separate from bounded call details.
@MainActor
final class CapabilityExecutionUsageStore: ObservableObject {
    static let shared = CapabilityExecutionUsageStore()
    @Published private(set) var byRoom: [String: [CapabilityExecutionSummary]] = [:]
    private var generations: [String: Double] = [:]

    func apply(_ rows: [CapabilityExecutionSummary]?, fromRoom room: String, generatedAt: Double) {
        guard let rows, !room.isEmpty, room.count <= 256, generatedAt.isFinite,
              generatedAt >= (generations[room] ?? 0) else { return }
        generations[room] = generatedAt
        let cutoff = max(CapabilityUsageStore.clearedAt,
                         Date().timeIntervalSince1970 * 1_000 - 30 * 86_400_000)
        var reports = Dictionary((byRoom[room] ?? []).filter { $0.lastUsedAt > cutoff }
            .map { (Self.key($0), $0) }, uniquingKeysWith: { _, right in right })
        for row in rows.prefix(128) where Self.valid(row) && row.lastUsedAt > cutoff {
            let key = Self.key(row)
            if let old = reports[key], old.source == "native-history", row.source != old.source { continue }
            reports[key] = row
        }
        byRoom[room] = Array(reports.values.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(512))
        if byRoom.count > 32 {
            let oldest = generations.min { $0.value < $1.value }?.key
            if let oldest { byRoom.removeValue(forKey: oldest); generations.removeValue(forKey: oldest) }
        }
    }

    func clear() { byRoom = [:]; generations = [:] }

    private static func key(_ row: CapabilityExecutionSummary) -> String {
        [row.agent, row.sessionId, row.kind.rawValue, row.name].joined(separator: "\u{1f}")
    }

    private static func valid(_ row: CapabilityExecutionSummary) -> Bool {
        !row.sessionId.isEmpty && row.sessionId.count <= 256 && !row.name.isEmpty && row.name.count <= 160
            && ["claude", "codex", "cursor", "grok"].contains(row.agent) && row.kind != .cli
            && ["native-history", "transcript"].contains(row.source)
            && row.count > 0 && row.count <= 20_000 && row.failures >= 0 && row.failures <= row.count
            && row.cancelled >= 0 && row.cancelled <= row.count
            && row.lastUsedAt.isFinite && row.lastUsedAt <= Date().timeIntervalSince1970 * 1_000 + 300_000
            && (row.durationMs ?? 0) >= 0 && (row.durationCount ?? 0) >= 0
            && (row.durationCount ?? 0) <= row.count
    }
}
