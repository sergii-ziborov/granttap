import Foundation
import SwiftUI

/// Honest link health: keys on device (**Linked**) vs Mac publisher freshness (**Live**).
/// Phone WebSocket up alone must never read as “Connected” when Mac is dead.
enum ConnectionPhase: Equatable {
    case demo
    case notLinked
    case phoneOffline
    case macOffline
    case needRepair
    case live
}

struct ConnectionSnapshot: Equatable {
    let phase: ConnectionPhase
    let linked: Bool
    let deviceName: String?
    let machineName: String?
    let roomShort: String?
    /// Age of last `sessions.status` in seconds; nil if never received.
    let catalogAgeSeconds: Int?

    /// Mac catalog is fresh enough to treat the publisher as healthy.
    static let macFreshnessSeconds: TimeInterval = 90

    static func shouldRecoverCatalogLink(for phase: ConnectionPhase) -> Bool {
        phase == .phoneOffline || phase == .macOffline || phase == .needRepair
    }

    var statusTitle: String {
        switch phase {
        case .demo: return L("Demo")
        case .notLinked: return L("Need pair")
        case .phoneOffline: return L("Offline")
        case .macOffline: return L("Mac offline")
        case .needRepair: return L("Need re-pair")
        case .live: return L("Live")
        }
    }

    var statusColor: Color {
        switch phase {
        case .demo: return Theme.muted
        case .notLinked, .needRepair: return Theme.riskMed
        case .phoneOffline: return Theme.muted
        case .macOffline: return Theme.riskMed
        case .live: return Theme.ok
        }
    }

    var detail: String {
        switch phase {
        case .demo:
            return L("Sample data — nothing reaches a computer.")
        case .notLinked:
            return L("No computers linked. Scan a QR from any Mac/PC agent chat to add one.")
        case .phoneOffline:
            return L("This iPhone is not on the relay. Tap Reconnect to reopen the link.")
        case .macOffline:
            return L("Phone is linked, but this computer has not published chats recently. If another Mac shows Live, tap Prefer for chats on it. Otherwise keep GrantTap monitor running, then Reconnect.")
        case .needRepair:
            return L("Keys are on this iPhone, but this computer never published (wrong room or old pair). Scan a fresh QR from that Mac/PC — existing other links stay. Or Prefer for chats on a Live computer.")
        case .live:
            if let machine = machineName, !machine.isEmpty {
                return String(format: L("“%@” is publishing chats."), machine)
            }
            return L("Phone and computer are in sync.")
        }
    }

    /// Whether this row should carry its repair button.
    ///
    /// A list that can show a broken computer without offering the fix beside
    /// it sends the user hunting through settings for it.
    static func needsAttention(_ phase: ConnectionPhase) -> Bool {
        phase == .phoneOffline || phase == .macOffline || phase == .needRepair
    }

    var primaryActionTitle: String {
        switch phase {
        case .demo: return L("Exit Demo")
        case .notLinked: return L("Add computer")
        case .phoneOffline, .macOffline: return L("Reconnect")
        case .needRepair: return L("Scan QR / Pair")
        case .live: return L("Reconnect")
        }
    }

    var showsPairEntry: Bool {
        phase != .demo
    }

    var footer: String {
        switch phase {
        case .demo:
            return L("Demo never executes a command on a computer.")
        case .notLinked:
            return L("Ask any agent to connect GrantTap — scan adds that computer. You can link several Macs/PCs.")
        case .phoneOffline:
            return L("Linked keys stay on this iPhone. Reconnect reopens the WebSocket; it does not require a new QR.")
        case .macOffline:
            return L("Pairing is still valid. Restart GrantTap monitor on that computer if Reconnect does not restore Live.")
        case .needRepair:
            return L("Do not delete other links. Scan a new QR only for this computer.")
        case .live:
            return L("Reconnect refreshes this link and asks the computer for a fresh chat list.")
        }
    }
}
