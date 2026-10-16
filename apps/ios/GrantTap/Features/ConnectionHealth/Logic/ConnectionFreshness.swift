import Foundation

enum ConnectionFreshness {
    /// Display-only grace for short socket blips. Delivery still uses the live
    /// transport and keeps decisions queued until the computer confirms them.
    static func phase(socketUp: Bool, disconnectedAt: Double, heartbeatAt: Double,
                      catalogAt: Double, socketUpSince: Double, now: Double) -> ConnectionPhase {
        let fresh = [heartbeatAt, catalogAt].contains {
            $0 > 0 && $0 >= now - ConnectionSnapshot.macFreshnessSeconds * 1_000
                && $0 <= now + 30_000
        }
        if !socketUp {
            let blip = disconnectedAt > 0 && now >= disconnectedAt && now - disconnectedAt < 1_800
            if blip {
                if fresh { return .live }
                if socketUpSince > 0 {
                    return catalogAt <= 0 && now - socketUpSince >= 180_000 ? .needRepair : .macOffline
                }
            }
            return .phoneOffline
        }
        if fresh { return .live }
        if catalogAt <= 0, socketUpSince > 0, now - socketUpSince >= 180_000 { return .needRepair }
        return .macOffline
    }
}
