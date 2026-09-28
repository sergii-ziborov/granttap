import Foundation

struct ChatComputerRoute: Equatable {
    let roomId: String
    let computerName: String
    let phase: ConnectionPhase
}

/// Multi-computer relay orchestration. Preferred room owns session catalog UI;
/// every linked room keeps a live socket for asks. Does not alter session-refresh
/// waiters beyond routing them through the preferred `relay`.
@MainActor
extension AppModel {
    /// Runtime socket / catalog health keyed by room (not persisted).
    ///
    /// `lastHeartbeatAt` is deliberately runtime-only: a persisted value would
    /// let a relaunch present a long-dead computer as Live before any packet
    /// has actually arrived.
    struct RoomRuntime: Equatable {
        var socketUp = false
        var socketUpSince: Double = 0
        var lastHeartbeatAt: Double = 0
    }


}
