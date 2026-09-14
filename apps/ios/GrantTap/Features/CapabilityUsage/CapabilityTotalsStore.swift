import Foundation
import SwiftUI

/// Period totals as counted on each computer.
///
/// The observation feed is bounded by a transport budget, so on a busy computer
/// the phone holds only the newest hours of events. Counting those events made
/// "last 7 days" mean "the last eighty calls", and a skill used yesterday read
/// as never used. Each computer counts its own period and sends the summary;
/// the phone only adds the computers together.
@MainActor
final class CapabilityTotalsStore: ObservableObject {
    static let shared = CapabilityTotalsStore()

    @Published private(set) var byRoom: [String: [CapabilityUsageTotal]] = [:]

    private init() {}

    func apply(_ totals: [CapabilityUsageTotal]?, fromRoom room: String?) {
        let key = room?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let totals, !totals.isEmpty else {
            byRoom[key] = nil
            return
        }
        byRoom[key] = totals
    }

    /// The published window that covers `days`, or nil when no computer sent one.
    func window(forDays days: Int) -> Int? {
        let wanted = days * 24
        let published = Set(byRoom.values.flatMap { $0.map(\.windowHours) })
        return published.contains(wanted) ? wanted : nil
    }

    /// Roll-up for one kind across every computer, or nil when unpublished.
    func total(kind: CapabilityUsageKind, windowHours: Int) -> CapabilityUsageTotal? {
        let rows = matching(windowHours: windowHours).filter { $0.kind == kind && $0.name == nil }
        return rows.isEmpty ? nil : Self.summed(rows, kind: kind, name: nil, windowHours: windowHours)
    }

    /// Named rows across every computer, merged by kind and name.
    func named(windowHours: Int) -> [CapabilityUsageTotal] {
        let rows = matching(windowHours: windowHours).filter { $0.name != nil }
        return Dictionary(grouping: rows) { "\($0.kind.rawValue)\u{1f}\($0.name ?? "")" }
            .values
            .compactMap { group in
                guard let first = group.first else { return nil }
                return Self.summed(group, kind: first.kind, name: first.name,
                                   windowHours: windowHours)
            }
            .sorted { ($0.count, $0.lastUsedAt) > ($1.count, $1.lastUsedAt) }
    }

    private func matching(windowHours: Int) -> [CapabilityUsageTotal] {
        byRoom.values.flatMap { $0.filter { $0.windowHours == windowHours } }
    }

    private static func summed(
        _ rows: [CapabilityUsageTotal], kind: CapabilityUsageKind, name: String?, windowHours: Int
    ) -> CapabilityUsageTotal {
        CapabilityUsageTotal(
            windowHours: windowHours, kind: kind, name: name,
            count: rows.reduce(0) { $0 + $1.count },
            failures: rows.reduce(0) { $0 + $1.failures },
            cancelled: rows.reduce(0) { $0 + $1.cancelled },
            lastUsedAt: rows.map(\.lastUsedAt).max() ?? 0
        )
    }
}
