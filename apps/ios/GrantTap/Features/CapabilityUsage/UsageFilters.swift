import SwiftUI

/// The window and the kinds Usage is read through.
///
/// Which calls count is a separate question from how they are drawn, and it
/// is the one that decides every number on the screen.
/// The window Usage is read through, in hours.
///
/// A day was the smallest choice, which is useless while watching a run that is
/// happening now — the question "what did the last hour cost" had no answer.
enum UsagePeriod: Int, CaseIterable, Identifiable {
    case hour = 1
    case today = 24
    case seven = 168
    case thirty = 720

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hour: return L("1h")
        case .today: return L("Today")
        default: return String(format: L("%d days"), rawValue / 24)
        }
    }

    /// Published totals arrive in whole-day windows, so a sub-day period has
    /// none and falls back to the calls actually observed.
    var publishedDays: Int? { rawValue % 24 == 0 ? rawValue / 24 : nil }
}

enum UsageKindFilter: String, CaseIterable, Identifiable {
    case all
    case mcp
    case skill
    case cli
    case failed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return L("All")
        case .skill: return L("Skills")
        case .failed: return L("Failed")
        case .mcp, .cli: return rawValue.uppercased()
        }
    }

    func includes(_ event: CapabilityUsageEvent) -> Bool {
        switch self {
        case .all: return true
        case .failed: return event.effectiveOutcome == .error
        default: return event.kind.rawValue == rawValue
        }
    }

    func includes(_ total: CapabilityUsageTotal) -> Bool {
        self == .all || (self == .failed ? total.failures > 0 : total.kind.rawValue == rawValue)
    }

    func selectedTotal(_ total: CapabilityUsageTotal) -> CapabilityUsageTotal? {
        guard includes(total) else { return nil }
        guard self == .failed else { return total }
        return CapabilityUsageTotal(
            windowHours: total.windowHours, kind: total.kind, name: total.name,
            count: total.failures, failures: total.failures, cancelled: 0,
            lastUsedAt: total.lastUsedAt
        )
    }

    func includes(_ summary: OperationalToolSummary) -> Bool {
        self == .all || (self == .failed ? summary.failures > 0 : summary.kind.rawValue == rawValue)
    }
}
